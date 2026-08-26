from pathlib import Path

path = Path('lib/screens/active_workout.dart')
text = path.read_text()
start = text.find('  Future<void> _scrollToSet(String exerciseId, String setId) async {')
end = text.find('  void _scrollToExercise(String exerciseId) {', start)
if start < 0 or end < 0:
    raise SystemExit('scrollToSet boundaries not found')
section = text[start:end]
section = section.replace(
    'if (setContext != null) {',
    'if (setContext != null && setContext.mounted) {',
)
section = section.replace(
    'if (revealedExerciseContext != null) {',
    'if (revealedExerciseContext != null && revealedExerciseContext.mounted) {',
)
if section.count('setContext.mounted') != 3:
    raise SystemExit('expected exactly three mounted set-context guards')
if section.count('revealedExerciseContext.mounted') != 1:
    raise SystemExit('expected exactly one revealed-exercise mounted guard')
path.write_text(text[:start] + section + text[end:])
