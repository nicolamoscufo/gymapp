from pathlib import Path

# Clean generated active-workout helpers no longer used after picker refactor.
active_path = Path('lib/screens/active_workout.dart')
active = active_path.read_text()
for block in [
    """  void _addCatalogExercisesToSession(List<ExerciseCatalogEntry> entries) {
    _addExercisesToSession(entries.map(_exerciseFromCatalogEntry).toList());
  }

""",
    """  void _addCustomExercisesToSession(List<Exercise> exercises) {
    _addExercisesToSession(exercises.map(_copyExerciseTemplate).toList());
  }

""",
]:
    if block not in active:
        raise RuntimeError('expected legacy add helper was not found')
    active = active.replace(block, '', 1)
active_path.write_text(active)

# Keep the free-workout entry inline in Allenati instead of overlaying calendar actions.
home_path = Path('lib/screens/home.dart')
home = home_path.read_text()
old_calendar = """  Widget _buildCalendarTab() {
    return CalendarScreen(
      schedules: schedules,
      history: history,
      defaultRestSeconds: _defaultRestSeconds,
      defaultBackoffReductionPercent: _defaultBackoffReductionPercent,
      onRefresh: _loadData,
      onSaveSchedules: _saveSchedules,
      showAppBar: false,
    );
  }
"""
new_calendar = """  Widget _buildCalendarTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('start-empty-workout'),
              onPressed: _startEmptyWorkout,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Allenamento libero'),
            ),
          ),
        ),
        Expanded(
          child: CalendarScreen(
            schedules: schedules,
            history: history,
            defaultRestSeconds: _defaultRestSeconds,
            defaultBackoffReductionPercent: _defaultBackoffReductionPercent,
            onRefresh: _loadData,
            onSaveSchedules: _saveSchedules,
            showAppBar: false,
          ),
        ),
      ],
    );
  }
"""
if home.count(old_calendar) != 1:
    raise RuntimeError('expected one calendar tab implementation')
home = home.replace(old_calendar, new_calendar, 1)

old_fab = """      floatingActionButton: _currentIndex == 1
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
original_fab = """      floatingActionButton: _currentIndex == 1
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
if home.count(old_fab) != 1:
    raise RuntimeError('expected v2 floating action button block')
home = home.replace(old_fab, original_fab, 1)
home_path.write_text(home)

# Make generated tests express behavior rather than incidental widget counts.
path = Path('test/workout_experience_v2_test.dart')
text = path.read_text()
start = text.index("  testWidgets('exercise menu can create and remove a superset'")
end = text.index("  testWidgets('exercise menu exposes reorder replace and delete actions'", start)
replacement = r'''  testWidgets('exercise menu can create and remove a superset', (tester) async {
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
          technique: IntensityTechnique.none,
        ),
        Exercise(
          name: 'Rematore',
          set: 1,
          reps: 10,
          weight: 60,
          muscleGroup: MuscleGroup.back,
          notes: '',
          technique: IntensityTechnique.none,
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
    await tester.tap(find.text('Rematore').last);
    await tester.pumpAndSettle();

    expect(find.text('Superset 1'), findsWidgets);

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestisci superset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rimuovi dal superset'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Azioni esercizio').first);
    await tester.pumpAndSettle();
    expect(find.text('Crea superset'), findsOneWidget);
  });

'''
text = text[:start] + replacement + text[end:]
text = text.replace(
    "          notes: '',\n        ),",
    "          notes: '',\n          technique: IntensityTechnique.none,\n        ),",
)
text = text.replace(
    "    expect(find.text('Panca'), findsNWidgets(2));\n    expect(find.byTooltip('Azioni esercizio'), findsNWidgets(2));",
    "    expect(find.text('Panca'), findsWidgets);\n    expect(find.byTooltip('Azioni esercizio'), findsNWidgets(2));",
)
path.write_text(text)
