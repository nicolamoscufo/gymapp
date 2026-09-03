from pathlib import Path
import re

path = Path('lib/screens/active_workout.dart')
text = path.read_text()
original = text

import_anchor = "import '../top_set_backoff.dart' as top_set_backoff;\n"
ui_import = "import '../ui/workout_components.dart';\n"
if ui_import not in text:
    if import_anchor not in text:
        raise SystemExit('top_set_backoff import anchor not found')
    text = text.replace(import_anchor, import_anchor + ui_import, 1)

compact_pattern = re.compile(
    r"  Widget _compactExerciseCard\(\{[\s\S]*?\n  \}\n\n  Future<void> _scrollToSet",
    re.MULTILINE,
)
compact_replacement = '''  Widget _compactExerciseCard({
    required WorkoutExercise exercise,
    required Color accent,
  }) {
    final completed = _completedSetCount(exercise);
    final total = exercise.sets.length;
    final isComplete = _isExerciseComplete(exercise);
    final nextIndex = _currentSetIndexFor(exercise);
    final nextSet = nextIndex >= 0 ? exercise.sets[nextIndex] : null;

    return WorkoutCompactExerciseCard(
      exerciseId: exercise.id,
      name: exercise.name,
      completedSets: completed,
      totalSets: total,
      isComplete: isComplete,
      accent: accent,
      nextPrescription: nextSet == null
          ? null
          : '${_formatWeight(nextSet.weight)} kg × ${nextSet.reps}',
      onTap: () => _focusExercise(exercise.id),
    );
  }

  Future<void> _scrollToSet'''
text, count = compact_pattern.subn(compact_replacement, text, count=1)
if count != 1:
    raise SystemExit(f'compact exercise replacement count={count}')

old_call = '''                child: _compactExerciseCard(
                  exercise: exercise,
                  accent: accent,
                  theme: theme,
                  colorScheme: colorScheme,
                ),'''
new_call = '''                child: _compactExerciseCard(
                  exercise: exercise,
                  accent: accent,
                ),'''
if old_call not in text:
    raise SystemExit('compact exercise call anchor not found')
text = text.replace(old_call, new_call, 1)

old_gradient = '''                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: isDark ? 0.18 : 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),'''
new_surface = '''                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                ),'''
if old_gradient not in text:
    raise SystemExit('expanded exercise gradient anchor not found')
text = text.replace(old_gradient, new_surface, 1)

table_header_pattern = re.compile(
    r"                      Row\(\n                        mainAxisAlignment: MainAxisAlignment\.spaceBetween,[\s\S]*?\n                      const Divider\(\),",
    re.MULTILINE,
)
text, count = table_header_pattern.subn(
    '''                      const WorkoutSetTableHeader(),
                      const Divider(),''',
    text,
    count=1,
)
if count != 1:
    raise SystemExit(f'set header replacement count={count}')

rest_pattern = re.compile(
    r"        bottomNavigationBar:[\s\S]*?\n        floatingActionButton:",
    re.MULTILINE,
)
rest_replacement = '''        bottomNavigationBar:
            activeRestExercise == null || activeRestSeconds == null
            ? null
            : WorkoutRestPanel(
                key: ValueKey('rest-mode-${activeRestExercise.id}'),
                exerciseName: activeRestExercise.name,
                countdown: _formatDuration(activeRestSeconds),
                progress: restProgress,
                nextSetId: restTarget?.set.id,
                nextExerciseName: restTarget?.exercise.name,
                nextSetLabel: restTarget == null
                    ? null
                    : 'Serie ${restTarget.setIndex + 1}${restTarget.set.type == SetType.normal ? '' : ' · ${restTarget.set.type.label}'}',
                nextPrescription: restTarget == null
                    ? null
                    : '${_formatWeight(restTarget.set.weight)} kg × ${restTarget.set.reps}',
                onMinusThirty: () =>
                    _subtractThirtySeconds(activeRestExercise),
                onPlusThirty: () => _addThirtySeconds(activeRestExercise),
                onSkip: () => _stopRestForExercise(activeRestExercise),
              ),
        floatingActionButton:'''
text, count = rest_pattern.subn(rest_replacement, text, count=1)
if count != 1:
    raise SystemExit(f'rest panel replacement count={count}')

if text == original:
    raise SystemExit('No changes produced')

path.write_text(text)
print('active_workout.dart refactor applied')
