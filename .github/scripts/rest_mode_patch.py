from pathlib import Path

active_path = Path('lib/screens/active_workout.dart')
text = active_path.read_text()

helper_marker = '''  void _submitSetFromKeyboard(
'''
helper = '''  ({WorkoutExercise exercise, ExerciseSet set, int setIndex})?
  _nextSetAfterRest(WorkoutExercise restExercise) {
    final supersetMembers = _exerciseManager.supersetMembers(restExercise);
    if (supersetMembers.length >= 2) {
      final memberIndex = supersetMembers.indexWhere(
        (member) => member.id == restExercise.id,
      );
      if (memberIndex >= 0) {
        for (var offset = 1; offset <= supersetMembers.length; offset++) {
          final candidate =
              supersetMembers[(memberIndex + offset) % supersetMembers.length];
          final setIndex = _currentSetIndexFor(candidate);
          if (setIndex >= 0) {
            return (
              exercise: candidate,
              set: candidate.sets[setIndex],
              setIndex: setIndex,
            );
          }
        }
      }
    }

    final currentSetIndex = _currentSetIndexFor(restExercise);
    if (currentSetIndex >= 0) {
      return (
        exercise: restExercise,
        set: restExercise.sets[currentSetIndex],
        setIndex: currentSetIndex,
      );
    }

    final exerciseIndex = session.exercises.indexWhere(
      (exercise) => exercise.id == restExercise.id,
    );
    if (exerciseIndex < 0) return null;
    for (var index = exerciseIndex + 1; index < session.exercises.length; index++) {
      final candidate = session.exercises[index];
      final setIndex = _currentSetIndexFor(candidate);
      if (setIndex >= 0) {
        return (
          exercise: candidate,
          set: candidate.sets[setIndex],
          setIndex: setIndex,
        );
      }
    }
    return null;
  }

'''
if '_nextSetAfterRest(WorkoutExercise restExercise)' not in text:
    if text.count(helper_marker) != 1:
        raise SystemExit('submit marker not found exactly once')
    text = text.replace(helper_marker, helper + helper_marker, 1)

build_anchor = '''    final activeRestSeconds = activeRestExercise == null
        ? null
        : _restController.remainingFor(activeRestExercise.id);
    final workoutReadiness = _workoutReadiness();
'''
build_replacement = '''    final activeRestSeconds = activeRestExercise == null
        ? null
        : _restController.remainingFor(activeRestExercise.id);
    final restTarget = activeRestExercise == null
        ? null
        : _nextSetAfterRest(activeRestExercise);
    final configuredRestSeconds = activeRestExercise == null
        ? null
        : _restController.configuredSecondsFor(activeRestExercise);
    final restProgress = activeRestSeconds == null ||
            configuredRestSeconds == null ||
            configuredRestSeconds <= 0
        ? null
        : (activeRestSeconds / configuredRestSeconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final workoutReadiness = _workoutReadiness();
'''
if build_anchor in text:
    text = text.replace(build_anchor, build_replacement, 1)
elif 'final restTarget = activeRestExercise == null' not in text:
    raise SystemExit('build rest anchor not found')

old_bottom = '''        bottomNavigationBar:
            activeRestExercise == null || activeRestSeconds == null
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recupero ${_formatDuration(activeRestSeconds)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              activeRestExercise.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '-30 sec',
                        onPressed: () =>
                            _subtractThirtySeconds(activeRestExercise),
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        tooltip: '+30 sec',
                        onPressed: () => _addThirtySeconds(activeRestExercise),
                        icon: const Icon(Icons.add),
                      ),
                      TextButton(
                        onPressed: () =>
                            _stopRestForExercise(activeRestExercise),
                        child: const Text('Salta'),
                      ),
                    ],
                  ),
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openExercisePicker,
          icon: const Icon(Icons.add),
          label: const Text('Esercizio'),
        ),
'''
new_bottom = '''        bottomNavigationBar:
            activeRestExercise == null || activeRestSeconds == null
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  key: ValueKey('rest-mode-${activeRestExercise.id}'),
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colorScheme.primary, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.timer_outlined,
                              color: colorScheme.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RECUPERO',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                Text(
                                  _formatDuration(activeRestSeconds),
                                  key: const ValueKey('rest-mode-countdown'),
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'dopo ${activeRestExercise.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (restProgress != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            key: const ValueKey('rest-mode-progress'),
                            value: restProgress,
                            minHeight: 6,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (restTarget != null)
                        Container(
                          key: ValueKey('rest-next-set-${restTarget.set.id}'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'PROSSIMO SET',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      restTarget.exercise.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      'Serie ${restTarget.setIndex + 1}${restTarget.set.type == SetType.normal ? '' : ' · ${restTarget.set.type.label}'}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_formatWeight(restTarget.set.weight)} kg\\n× ${restTarget.set.reps}',
                                key: const ValueKey('rest-next-prescription'),
                                textAlign: TextAlign.right,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          key: const ValueKey('rest-workout-complete'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer.withValues(
                              alpha: isDark ? 0.35 : 0.65,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: colorScheme.tertiary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Ultimo set completato',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      'Recupera e poi puoi terminare l’allenamento.',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('rest-minus-30'),
                              onPressed: () =>
                                  _subtractThirtySeconds(activeRestExercise),
                              icon: const Icon(Icons.remove),
                              label: const Text('30 s'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('rest-plus-30'),
                              onPressed: () =>
                                  _addThirtySeconds(activeRestExercise),
                              icon: const Icon(Icons.add),
                              label: const Text('30 s'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('rest-skip'),
                              onPressed: () =>
                                  _stopRestForExercise(activeRestExercise),
                              child: const Text('Salta'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        floatingActionButton: activeRestExercise == null
            ? FloatingActionButton.extended(
                onPressed: _openExercisePicker,
                icon: const Icon(Icons.add),
                label: const Text('Esercizio'),
              )
            : null,
'''
if old_bottom in text:
    text = text.replace(old_bottom, new_bottom, 1)
elif "key: ValueKey('rest-mode-${activeRestExercise.id}')" not in text:
    raise SystemExit('old bottom rest panel not found')

active_path.write_text(text)

test_path = Path('test/workout_ux_polish_v2_test.dart')
test_text = test_path.read_text()
if 'rest mode surfaces the next set and thumb controls' not in test_text:
    insertion = r'''

  testWidgets('rest mode surfaces the next set and thumb controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final first = ExerciseSet(weight: 50, reps: 8);
    final second = ExerciseSet(weight: 52.5, reps: 8);
    final exercise = _exercise('Bench', sets: [first, second])
      ..restSeconds = 90;
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
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('rest-next-set-${second.id}')), findsOneWidget);
    expect(find.text('PROSSIMO SET'), findsOneWidget);
    expect(find.textContaining('52.5 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-minus-30')), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-plus-30')), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-skip')), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Esercizio'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('rest-skip')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(ValueKey('rest-mode-${exercise.id}')), findsNothing);
    expect(find.widgetWithText(FloatingActionButton, 'Esercizio'), findsOneWidget);
  });

  testWidgets('rest mode follows the next superset round', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final a1 = ExerciseSet(weight: 60, reps: 8);
    final a2 = ExerciseSet(weight: 62.5, reps: 8);
    final b1 = ExerciseSet(weight: 30, reps: 10);
    final b2 = ExerciseSet(weight: 32.5, reps: 10);
    final a = _exercise('Bench', sets: [a1, a2], supersetGroup: 7)
      ..restSeconds = 90;
    final b = _exercise('Row', sets: [b1, b2], supersetGroup: 7)
      ..restSeconds = 90;
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
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(ValueKey('rest-mode-${a.id}')), findsNothing);

    final completeB = find.byKey(ValueKey('complete-${b1.id}'));
    await tester.ensureVisible(completeB);
    await tester.tap(completeB);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(ValueKey('rest-mode-${b.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('rest-next-set-${a2.id}')), findsOneWidget);
    expect(find.text('Bench'), findsWidgets);
    expect(find.textContaining('62.5 kg'), findsOneWidget);
  });
'''
    closing = test_text.rfind('\n}')
    if closing < 0:
        raise SystemExit('test file closing brace not found')
    test_text = test_text[:closing] + insertion + test_text[closing:]
    test_path.write_text(test_text)
