from pathlib import Path

active_path = Path('lib/screens/active_workout.dart')
text = active_path.read_text()

field_anchor = "  final ScrollController _workoutScrollController = ScrollController();\n"
field_insert = "  final ScrollController _workoutScrollController = ScrollController();\n  String? _focusedExerciseId;\n"
if "String? _focusedExerciseId;" not in text:
    if field_anchor not in text:
        raise SystemExit('focus field anchor not found')
    text = text.replace(field_anchor, field_insert, 1)

helper_anchor = "  GlobalKey _setRowKey(String setId) {\n    return _setRowKeys.putIfAbsent(setId, GlobalKey.new);\n  }\n\n"
helper = '''  String? _effectiveFocusedExerciseId() {
    if (widget.editCompletedSession) return null;
    final explicitId = _focusedExerciseId;
    if (explicitId != null &&
        session.exercises.any((exercise) => exercise.id == explicitId)) {
      return explicitId;
    }
    for (final exercise in session.exercises) {
      if (exercise.sets.any((set) => !set.isCompleted)) return exercise.id;
    }
    return session.exercises.isEmpty ? null : session.exercises.last.id;
  }

  bool _isExerciseComplete(WorkoutExercise exercise) =>
      exercise.sets.isNotEmpty && exercise.sets.every((set) => set.isCompleted);

  int _completedSetCount(WorkoutExercise exercise) =>
      exercise.sets.where((set) => set.isCompleted).length;

  void _focusExercise(String exerciseId, {bool scroll = true}) {
    if (widget.editCompletedSession) {
      if (scroll) _scrollToExercise(exerciseId);
      return;
    }
    if (_focusedExerciseId != exerciseId) {
      setState(() => _focusedExerciseId = exerciseId);
    }
    if (scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToExercise(exerciseId);
      });
    }
  }

  Widget _compactExerciseCard({
    required WorkoutExercise exercise,
    required Color accent,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final completed = _completedSetCount(exercise);
    final total = exercise.sets.length;
    final isComplete = _isExerciseComplete(exercise);
    final nextIndex = _currentSetIndexFor(exercise);
    final nextSet = nextIndex >= 0 ? exercise.sets[nextIndex] : null;
    final status = isComplete
        ? 'Completato · $completed/$total set'
        : nextSet == null
        ? '$completed/$total set'
        : '$completed/$total set · prossimo ${_formatWeight(nextSet.weight)} kg × ${nextSet.reps}';

    return Card(
      key: ValueKey('compact-exercise-${exercise.id}'),
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: InkWell(
        key: ValueKey('expand-exercise-${exercise.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _focusExercise(exercise.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 38,
                decoration: BoxDecoration(
                  color: isComplete ? colorScheme.tertiary : accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            exercise.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (isComplete)
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: colorScheme.tertiary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      key: ValueKey('compact-progress-${exercise.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.expand_more, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

'''
if '_effectiveFocusedExerciseId()' not in text:
    if helper_anchor not in text:
        raise SystemExit('focus helper anchor not found')
    text = text.replace(helper_anchor, helper_anchor + helper, 1)

old_scroll = '''  void _scrollToExercise(String exerciseId) {
    final context = _exerciseCardKeys[exerciseId]?.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }
'''
new_scroll = '''  void _scrollToExercise(String exerciseId) {
    final context = _exerciseCardKeys[exerciseId]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  void _selectExerciseFromJumpBar(String exerciseId) {
    _focusExercise(exerciseId);
  }
'''
if '_selectExerciseFromJumpBar' not in text:
    if old_scroll not in text:
        raise SystemExit('scroll helper anchor not found')
    text = text.replace(old_scroll, new_scroll, 1)

toggle_anchor = '''      _advanceSupersetNavigation(exercise, setIndex);
      if (prEvent != null) {
'''
toggle_replace = '''      final focusTarget = _exerciseManager.nextSupersetMemberAfterSet(
        exercise,
        setIndex,
      );
      if (focusTarget != null && mounted) {
        setState(() => _focusedExerciseId = focusTarget.id);
      }
      _advanceSupersetNavigation(exercise, setIndex);
      if (prEvent != null) {
'''
if 'final focusTarget = _exerciseManager.nextSupersetMemberAfterSet' not in text:
    if toggle_anchor not in text:
        raise SystemExit('toggle focus anchor not found')
    text = text.replace(toggle_anchor, toggle_replace, 1)

handoff_anchor = '''    setState(() {
      _handoffSetId = set.id;
      _handoffPulseEmphasis = true;
    });
'''
handoff_replace = '''    setState(() {
      _focusedExerciseId = exercise.id;
      _handoffSetId = set.id;
      _handoffPulseEmphasis = true;
    });
'''
if '_focusedExerciseId = exercise.id;\n      _handoffSetId' not in text:
    if handoff_anchor not in text:
        raise SystemExit('handoff focus anchor not found')
    text = text.replace(handoff_anchor, handoff_replace, 1)

text = text.replace(
    'onSelected: _scrollToExercise,',
    'onSelected: _selectExerciseFromJumpBar,',
    1,
)

build_anchor = '''    final workoutReadiness = _workoutReadiness();

    return PopScope(
'''
build_replace = '''    final workoutReadiness = _workoutReadiness();
    final focusedExerciseId = _effectiveFocusedExerciseId();

    return PopScope(
'''
if 'final focusedExerciseId = _effectiveFocusedExerciseId();' not in text:
    if build_anchor not in text:
        raise SystemExit('build focus anchor not found')
    text = text.replace(build_anchor, build_replace, 1)

list_anchor = '''        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
'''
list_replace = '''        body: ListView.builder(
          controller: _workoutScrollController,
          padding: const EdgeInsets.only(bottom: 96),
'''
if 'body: ListView.builder(\n          controller: _workoutScrollController,' not in text:
    if list_anchor not in text:
        raise SystemExit('list controller anchor not found')
    text = text.replace(list_anchor, list_replace, 1)

card_anchor = '''            final historicalEstimatedOneRepMax =
                historicalBestEstimatedOneRepMax(
                  history: widget.history,
                  exerciseName: exercise.name,
                  excludeSessionId: session.id,
                );

            return Card(
              key: _exerciseCardKey(exercise.id),
'''
card_replace = '''            final historicalEstimatedOneRepMax =
                historicalBestEstimatedOneRepMax(
                  history: widget.history,
                  exerciseName: exercise.name,
                  excludeSessionId: session.id,
                );
            final isFocusedExercise =
                widget.editCompletedSession || focusedExerciseId == exercise.id;
            if (!isFocusedExercise) {
              return KeyedSubtree(
                key: _exerciseCardKey(exercise.id),
                child: _compactExerciseCard(
                  exercise: exercise,
                  accent: accent,
                  theme: theme,
                  colorScheme: colorScheme,
                ),
              );
            }

            return Card(
              key: _exerciseCardKey(exercise.id),
'''
if 'final isFocusedExercise =' not in text:
    if card_anchor not in text:
        raise SystemExit('exercise card focus anchor not found')
    text = text.replace(card_anchor, card_replace, 1)

active_path.write_text(text)

test_path = Path('test/workout_ux_polish_v2_test.dart')
tests = test_path.read_text()
if 'focus mode compacts non-active exercises and promotes on tap' not in tests:
    insertion = r'''

  testWidgets('focus mode compacts non-active exercises and promotes on tap', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final firstSet = ExerciseSet(weight: 70, reps: 8);
    final secondSet = ExerciseSet(weight: 30, reps: 10);
    final first = _exercise('Bench', sets: [firstSet])..restSeconds = 0;
    final second = _exercise('Row', sets: [secondSet])..restSeconds = 0;
    final session = _session([first, second]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('compact-exercise-${first.id}')), findsNothing);
    expect(find.byKey(ValueKey('compact-exercise-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thumb-complete-${firstSet.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thumb-complete-${secondSet.id}')), findsNothing);

    await tester.tap(find.byKey(ValueKey('expand-exercise-${second.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('compact-exercise-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('compact-exercise-${second.id}')), findsNothing);
    expect(find.byKey(ValueKey('thumb-complete-${secondSet.id}')), findsOneWidget);
  });

  testWidgets('focus mode follows smart exercise completion', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final firstSet = ExerciseSet(weight: 70, reps: 8);
    final secondSet = ExerciseSet(weight: 30, reps: 10);
    final first = _exercise('Bench', sets: [firstSet])..restSeconds = 0;
    final second = _exercise('Row', sets: [secondSet])..restSeconds = 0;
    final session = _session([first, second]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('thumb-complete-${firstSet.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('compact-exercise-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('compact-exercise-${second.id}')), findsNothing);
    expect(find.byKey(ValueKey('thumb-complete-${secondSet.id}')), findsOneWidget);
  });
'''
    idx = tests.rfind('\n}')
    if idx < 0:
        raise SystemExit('test closing brace not found')
    tests = tests[:idx] + insertion + tests[idx:]

test_path.write_text(tests)
