from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {count}')
    path.write_text(text.replace(old, new, 1))


screen = Path('lib/screens/active_workout.dart')
replace_once(
    screen,
    '''  final Set<String> _exerciseIdsAddedToScheduleThisFinish = {};
  final ActiveWorkoutSessionController _sessionPersistence =
''',
    '''  final Set<String> _exerciseIdsAddedToScheduleThisFinish = {};
  int _prBannerGeneration = 0;
  Timer? _prBannerTimer;
  final ActiveWorkoutSessionController _sessionPersistence =
''',
    'PR banner lifecycle state',
)

replace_once(
    screen,
    '''  void _toggleSetCompleted(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
''',
    '''  void _showPersonalRecordCelebration(ActiveWorkoutPrEvent event) {
    if (!mounted) return;

    final generation = ++_prBannerGeneration;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    _prBannerTimer?.cancel();
    _prBannerTimer = null;
    messenger.removeCurrentMaterialBanner();
    HapticFeedback.mediumImpact();
    messenger.showMaterialBanner(
      MaterialBanner(
        key: const ValueKey('live-pr-banner'),
        backgroundColor: colorScheme.tertiaryContainer,
        leading: Icon(Icons.emoji_events, color: colorScheme.tertiary),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.headline,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(event.exerciseName),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: event.kinds
                  .map(
                    (kind) => Chip(
                      key: ValueKey('live-pr-${kind.name}'),
                      label: Text(kind.displayLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('dismiss-live-pr'),
            onPressed: () {
              _prBannerGeneration++;
              _prBannerTimer?.cancel();
              _prBannerTimer = null;
              messenger.hideCurrentMaterialBanner();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    _prBannerTimer = Timer(const Duration(seconds: 4), () {
      _prBannerTimer = null;
      if (!mounted || generation != _prBannerGeneration) return;
      _prBannerGeneration++;
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    });
  }

  void _toggleSetCompleted(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
  ) {
''',
    'PR celebration method insertion',
)

replace_once(
    screen,
    '''    _saveCurrentSession();
    if (willComplete && !widget.editCompletedSession) {
      if (_shouldStartRestAfterSet(exercise, setIndex)) {
        _startRestForExercise(exercise);
      }
      _advanceSupersetNavigation(exercise, setIndex);
    }

    final delta = _setVolumeDelta(exercise, set, setIndex);
    if (willComplete && delta != null && delta > 0 && mounted) {
''',
    '''    _saveCurrentSession();
    final prEvent = willComplete
        ? _workoutInsights.personalRecordEventFor(exercise, set, setIndex)
        : null;
    if (willComplete && !widget.editCompletedSession) {
      if (_shouldStartRestAfterSet(exercise, setIndex)) {
        _startRestForExercise(exercise);
      }
      _advanceSupersetNavigation(exercise, setIndex);
      if (prEvent != null) {
        _showPersonalRecordCelebration(prEvent);
      }
    }

    final delta = _setVolumeDelta(exercise, set, setIndex);
    if (willComplete &&
        prEvent == null &&
        delta != null &&
        delta > 0 &&
        mounted) {
''',
    'toggle PR event integration',
)

replace_once(
    screen,
    '''  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restController.dispose();
    _durationTimer?.cancel();
''',
    '''  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prBannerTimer?.cancel();
    _prBannerTimer = null;
    _restController.dispose();
    _durationTimer?.cancel();
''',
    'PR banner timer dispose',
)

foundations = Path('test/refactor_foundations_test.dart')
text = foundations.read_text()
anchor = '''  test('active workout insights ignore warm-up sets for PRs', () {
'''
if anchor not in text:
    raise SystemExit('foundations anchor missing')
new_test = '''  test('active workout insights exposes structured PR celebration event', () {
    final historical = workoutExercise(
      id: 'historical_press',
      name: 'Panca piana',
      weight: 80,
      reps: 5,
    );
    final current = workoutExercise(
      id: 'current_press',
      name: 'Panca piana',
      weight: 82.5,
      reps: 5,
    );
    final insights = ActiveWorkoutInsights(
      history: [workoutSession(id: 'old_session', exercise: historical)],
      currentSessionId: 'current_session',
    );

    final event = insights.personalRecordEventFor(
      current,
      current.sets.single,
      0,
    );

    expect(event, isNotNull);
    expect(event!.exerciseName, 'Panca piana');
    expect(event.kinds, [
      ActiveWorkoutPrKind.weight,
      ActiveWorkoutPrKind.setVolume,
      ActiveWorkoutPrKind.estimatedOneRepMax,
      ActiveWorkoutPrKind.exerciseVolume,
    ]);
    expect(event.headline, '4 nuovi record personali!');
    expect(event.summary, 'Carico · Volume set · e1RM · Volume esercizio');
    expect(event.legacyLabels, ['PR kg', 'PR set', 'PR e1RM', 'PR volume']);
  });

'''
foundations.write_text(text.replace(anchor, new_test + anchor, 1))

screen_test = Path('test/active_workout_screen_test.dart')
text = screen_test.read_text()
if not text.endswith('\n}\n'):
    raise SystemExit('screen test final brace missing')
widget_test = r'''
  testWidgets('live PR banner celebrates structured records without duplicate volume snackbar', (
    tester,
  ) async {
    final historicalExercise = WorkoutExercise(
      id: 'historical_bench',
      name: 'Panca',
      notes: '',
      technique: IntensityTechnique.none,
      sets: [
        ExerciseSet(
          id: 'historical_set',
          weight: 80,
          reps: 5,
          isCompleted: true,
        ),
      ],
    );
    final historical = WorkoutSession(
      id: 'historical_session',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 8, 20, 10),
      endTime: DateTime(2026, 8, 20, 11),
      exercises: [historicalExercise],
    );
    final current = WorkoutSession(
      id: 'current_session',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 8, 26, 10),
      endTime: DateTime(2026, 8, 26, 10),
      exercises: [
        WorkoutExercise(
          id: 'current_bench',
          name: 'Panca',
          notes: '',
          technique: IntensityTechnique.none,
          restSeconds: 90,
          sets: [
            ExerciseSet(id: 'current_pr_set', weight: 82.5, reps: 6),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.resume(
          resumedSession: current,
          history: [historical],
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final complete = find.byKey(const ValueKey('complete-current_pr_set'));
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('live-pr-banner')), findsOneWidget);
    expect(find.text('5 nuovi record personali!'), findsOneWidget);
    expect(find.text('Panca'), findsWidgets);
    expect(find.byKey(const ValueKey('live-pr-weight')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-pr-reps')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-pr-estimatedOneRepMax')),
      findsOneWidget,
    );
    expect(find.textContaining('volume set migliorato'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
'''
screen_test.write_text(text[:-3] + widget_test + '\n}\n')
