from pathlib import Path

active_path = Path('lib/screens/active_workout.dart')
text = active_path.read_text()

fields_anchor = '''  final Map<String, GlobalKey> _exerciseCardKeys = {};
  final Set<String> _exerciseIdsAddedToScheduleThisFinish = {};
'''
fields_replacement = '''  final Map<String, GlobalKey> _exerciseCardKeys = {};
  final Map<String, GlobalKey> _setRowKeys = {};
  final ScrollController _workoutScrollController = ScrollController();
  String? _handoffSetId;
  bool _handoffPulseEmphasis = false;
  Timer? _handoffPulseTimer;
  Timer? _handoffClearTimer;
  final Set<String> _exerciseIdsAddedToScheduleThisFinish = {};
'''
if fields_anchor in text:
    text = text.replace(fields_anchor, fields_replacement, 1)
elif 'final Map<String, GlobalKey> _setRowKeys' not in text:
    raise SystemExit('fields anchor not found')

helper_anchor = '''  GlobalKey _exerciseCardKey(String exerciseId) {
    return _exerciseCardKeys.putIfAbsent(exerciseId, GlobalKey.new);
  }

'''
helper_replacement = '''  GlobalKey _exerciseCardKey(String exerciseId) {
    return _exerciseCardKeys.putIfAbsent(exerciseId, GlobalKey.new);
  }

  GlobalKey _setRowKey(String setId) {
    return _setRowKeys.putIfAbsent(setId, GlobalKey.new);
  }

  Future<void> _scrollToSet(String exerciseId, String setId) async {
    var setContext = _setRowKeys[setId]?.currentContext;
    if (setContext != null) {
      await Scrollable.ensureVisible(
        setContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
      return;
    }

    final exerciseContext = _exerciseCardKeys[exerciseId]?.currentContext;
    if (exerciseContext != null) {
      await Scrollable.ensureVisible(
        exerciseContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));
      setContext = _setRowKeys[setId]?.currentContext;
      if (setContext != null) {
        await Scrollable.ensureVisible(
          setContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.28,
        );
      }
      return;
    }

    if (!_workoutScrollController.hasClients || session.exercises.isEmpty) {
      return;
    }
    final exerciseIndex = session.exercises.indexWhere(
      (exercise) => exercise.id == exerciseId,
    );
    if (exerciseIndex < 0) return;

    final position = _workoutScrollController.position;
    final fraction = session.exercises.length <= 1
        ? 0.0
        : exerciseIndex / (session.exercises.length - 1);
    await _workoutScrollController.animateTo(
      position.maxScrollExtent * fraction,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 24));

    final revealedExerciseContext =
        _exerciseCardKeys[exerciseId]?.currentContext;
    if (revealedExerciseContext != null) {
      await Scrollable.ensureVisible(
        revealedExerciseContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 24));
    setContext = _setRowKeys[setId]?.currentContext;
    if (setContext != null) {
      await Scrollable.ensureVisible(
        setContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
    }
  }

'''
if helper_anchor in text:
    text = text.replace(helper_anchor, helper_replacement, 1)
elif 'Future<void> _scrollToSet(String exerciseId, String setId)' not in text:
    raise SystemExit('exercise key helper anchor not found')

handler_anchor = '''  void _handleRestFinished(String exerciseId, String? exerciseName) {
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

'''
handler_replacement = '''  void _triggerPostRestHandoff(
    WorkoutExercise exercise,
    ExerciseSet set,
  ) {
    _handoffPulseTimer?.cancel();
    _handoffClearTimer?.cancel();
    var pulseTransitions = 0;
    setState(() {
      _handoffSetId = set.id;
      _handoffPulseEmphasis = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToSet(exercise.id, set.id);
      }
    });

    _handoffPulseTimer = Timer.periodic(
      const Duration(milliseconds: 260),
      (timer) {
        if (!mounted || _handoffSetId != set.id) {
          timer.cancel();
          return;
        }
        pulseTransitions++;
        setState(() {
          _handoffPulseEmphasis = !_handoffPulseEmphasis;
        });
        if (pulseTransitions >= 4) {
          timer.cancel();
          _handoffPulseTimer = null;
        }
      },
    );
    _handoffClearTimer = Timer(const Duration(milliseconds: 1800), () {
      _handoffClearTimer = null;
      if (!mounted || _handoffSetId != set.id) return;
      setState(() {
        _handoffSetId = null;
        _handoffPulseEmphasis = false;
      });
    });
  }

  void _handleRestFinished(String exerciseId, String? exerciseName) {
    WorkoutExercise? restExercise;
    for (final candidate in session.exercises) {
      if (candidate.id == exerciseId) {
        restExercise = candidate;
        break;
      }
    }
    final handoffTarget = restExercise == null
        ? null
        : _nextSetAfterRest(restExercise);

    _saveCurrentSession();
    if (handoffTarget == null) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    SystemSound.play(SystemSoundType.alert);
    LocalNotificationService.showRestFinished(exerciseName ?? '');

    if (!mounted) return;
    if (handoffTarget != null) {
      _triggerPostRestHandoff(handoffTarget.exercise, handoffTarget.set);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          handoffTarget == null
              ? (exerciseName == null
                    ? 'Recupero finito.'
                    : 'Recupero finito: $exerciseName.')
              : 'Recupero finito · ${handoffTarget.exercise.name}: ${_formatWeight(handoffTarget.set.weight)} kg × ${handoffTarget.set.reps}.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

'''
if handler_anchor in text:
    text = text.replace(handler_anchor, handler_replacement, 1)
elif 'void _triggerPostRestHandoff(' not in text:
    raise SystemExit('rest finished handler anchor not found')

list_anchor = '''        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
'''
list_replacement = '''        body: ListView.builder(
          controller: _workoutScrollController,
          padding: const EdgeInsets.only(bottom: 96),
'''
if list_anchor in text:
    text = text.replace(list_anchor, list_replacement, 1)
elif 'controller: _workoutScrollController' not in text:
    raise SystemExit('list view anchor not found')

set_vars_anchor = '''                        final currentSetIndex = _currentSetIndexFor(exercise);
                        final isCurrentSet = setIndex == currentSetIndex;
                        final setMetadataSummary = _setMetadataSummary(exSet);
'''
set_vars_replacement = '''                        final currentSetIndex = _currentSetIndexFor(exercise);
                        final isCurrentSet = setIndex == currentSetIndex;
                        final isHandoffSet = _handoffSetId == exSet.id;
                        final setMetadataSummary = _setMetadataSummary(exSet);
'''
if set_vars_anchor in text:
    text = text.replace(set_vars_anchor, set_vars_replacement, 1)
elif 'final isHandoffSet = _handoffSetId == exSet.id;' not in text:
    raise SystemExit('set vars anchor not found')

container_anchor = '''                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                            decoration: BoxDecoration(
'''
container_replacement = '''                          child: AnimatedContainer(
                            key: _setRowKey(exSet.id),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOut,
                            transformAlignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(
                              isHandoffSet && _handoffPulseEmphasis ? 1.012 : 1.0,
                              isHandoffSet && _handoffPulseEmphasis ? 1.012 : 1.0,
                              1.0,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                            decoration: BoxDecoration(
'''
if container_anchor in text:
    text = text.replace(container_anchor, container_replacement, 1)
elif 'key: _setRowKey(exSet.id)' not in text:
    raise SystemExit('set container anchor not found')

color_anchor = '''                              color: exSet.isCompleted
                                  ? colorScheme.tertiaryContainer.withValues(
                                      alpha: isDark ? 0.38 : 0.62,
                                    )
                                  : isCurrentSet
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: isDark ? 0.28 : 0.48,
                                    )
                                  : Colors.transparent,
'''
color_replacement = '''                              color: exSet.isCompleted
                                  ? colorScheme.tertiaryContainer.withValues(
                                      alpha: isDark ? 0.38 : 0.62,
                                    )
                                  : isHandoffSet
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: isDark
                                          ? (_handoffPulseEmphasis ? 0.58 : 0.36)
                                          : (_handoffPulseEmphasis ? 0.82 : 0.58),
                                    )
                                  : isCurrentSet
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: isDark ? 0.28 : 0.48,
                                    )
                                  : Colors.transparent,
'''
if color_anchor in text:
    text = text.replace(color_anchor, color_replacement, 1)
elif ': isHandoffSet\n                                  ? colorScheme.primaryContainer' not in text:
    raise SystemExit('set color anchor not found')

border_anchor = '''                              border: Border.all(
                                color: exSet.isCompleted
                                    ? colorScheme.tertiary.withValues(
                                        alpha: 0.35,
                                      )
                                    : isCurrentSet
                                    ? colorScheme.primary
                                    : Colors.transparent,
                                width: isCurrentSet ? 1.6 : 1,
                              ),
'''
border_replacement = '''                              border: Border.all(
                                color: exSet.isCompleted
                                    ? colorScheme.tertiary.withValues(
                                        alpha: 0.35,
                                      )
                                    : isHandoffSet || isCurrentSet
                                    ? colorScheme.primary
                                    : Colors.transparent,
                                width: isHandoffSet
                                    ? (_handoffPulseEmphasis ? 2.8 : 2.0)
                                    : isCurrentSet
                                    ? 1.6
                                    : 1,
                              ),
                              boxShadow: isHandoffSet && _handoffPulseEmphasis
                                  ? [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.24,
                                        ),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
'''
if border_anchor in text:
    text = text.replace(border_anchor, border_replacement, 1)
elif 'boxShadow: isHandoffSet && _handoffPulseEmphasis' not in text:
    raise SystemExit('set border anchor not found')

handoff_anchor = '''                                if (isCurrentSet && !exSet.isCompleted)
                                  Padding(
'''
handoff_replacement = '''                                if (isHandoffSet && !exSet.isCompleted)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      72,
                                      6,
                                      8,
                                      0,
                                    ),
                                    child: Container(
                                      key: ValueKey('handoff-set-${exSet.id}'),
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(
                                          alpha: isDark ? 0.18 : 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.bolt,
                                            size: 17,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'TOCCA A TE',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.7,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (isCurrentSet && !exSet.isCompleted)
                                  Padding(
'''
if handoff_anchor in text:
    text = text.replace(handoff_anchor, handoff_replacement, 1)
elif "key: ValueKey('handoff-set-${exSet.id}')" not in text:
    raise SystemExit('handoff banner anchor not found')

dispose_anchor = '''    _prBannerTimer?.cancel();
    _prBannerTimer = null;
    _restController.dispose();
    _durationTimer?.cancel();
'''
dispose_replacement = '''    _prBannerTimer?.cancel();
    _prBannerTimer = null;
    _handoffPulseTimer?.cancel();
    _handoffPulseTimer = null;
    _handoffClearTimer?.cancel();
    _handoffClearTimer = null;
    _restController.dispose();
    _durationTimer?.cancel();
    _workoutScrollController.dispose();
'''
if dispose_anchor in text:
    text = text.replace(dispose_anchor, dispose_replacement, 1)
elif '_workoutScrollController.dispose();' not in text:
    raise SystemExit('dispose anchor not found')

active_path.write_text(text)

test_path = Path('test/workout_ux_polish_v2_test.dart')
test_text = test_path.read_text()
if 'rest expiry hands off to the exact next set' not in test_text:
    insertion = r'''

  testWidgets('rest expiry hands off to the exact next set', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final first = ExerciseSet(weight: 50, reps: 8);
    final second = ExerciseSet(weight: 52.5, reps: 8);
    final exercise = _exercise('Bench', sets: [first, second])
      ..restSeconds = 1;
    final session = _session([exercise]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final complete = find.byKey(ValueKey('thumb-complete-${first.id}'));
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pump();
    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsNothing);
    expect(find.byKey(ValueKey('current-set-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('handoff-set-${second.id}')), findsOneWidget);
    expect(find.text('TOCCA A TE'), findsOneWidget);
    expect(find.textContaining('Recupero finito · Bench'), findsOneWidget);
  });

  testWidgets('rest expiry hands a superset to the next round leader', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final a1 = ExerciseSet(weight: 60, reps: 8);
    final a2 = ExerciseSet(weight: 62.5, reps: 8);
    final b1 = ExerciseSet(weight: 30, reps: 10);
    final b2 = ExerciseSet(weight: 32.5, reps: 10);
    final a = _exercise('Bench', sets: [a1, a2], supersetGroup: 7)
      ..restSeconds = 1;
    final b = _exercise('Row', sets: [b1, b2], supersetGroup: 7)
      ..restSeconds = 1;
    final session = _session([a, b]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final completeA = find.byKey(ValueKey('complete-${a1.id}'));
    await tester.ensureVisible(completeA);
    await tester.tap(completeA);
    await tester.pump();
    expect(find.byKey(ValueKey('rest-mode-${a.id}')), findsNothing);

    final completeB = find.byKey(ValueKey('complete-${b1.id}'));
    await tester.ensureVisible(completeB);
    await tester.tap(completeB);
    await tester.pump();
    expect(find.byKey(ValueKey('rest-mode-${b.id}')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(ValueKey('rest-mode-${b.id}')), findsNothing);
    expect(find.byKey(ValueKey('handoff-set-${a2.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('current-set-${a2.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('handoff-set-${b2.id}')), findsNothing);
  });
'''
    head, sep, tail = test_text.rpartition('\n}')
    if not sep:
        raise SystemExit('test file closing brace not found')
    test_text = head + insertion + '\n}' + tail

test_path.write_text(test_text)
