from pathlib import Path
import re

# Make switch control flow explicit and use an icon guaranteed by Material.
path = Path('lib/ai_coach/ai_plan_action_service.dart')
text = path.read_text()
text = text.replace("          exercise.weight = action.parsedValue as double;\n        case 'sets':", "          exercise.weight = action.parsedValue as double;\n          break;\n        case 'sets':")
text = text.replace("          exercise.set = action.parsedValue as int;\n        case 'reps':", "          exercise.set = action.parsedValue as int;\n          break;\n        case 'reps':")
text = text.replace("          exercise.reps = action.parsedValue as int;\n        case 'target_min_reps':", "          exercise.reps = action.parsedValue as int;\n          break;\n        case 'target_min_reps':")
text = text.replace("          exercise.targetMinReps = action.parsedValue as int;\n        case 'target_max_reps':", "          exercise.targetMinReps = action.parsedValue as int;\n          break;\n        case 'target_max_reps':")
text = text.replace("          exercise.targetMaxReps = action.parsedValue as int;\n        case 'rest_seconds':", "          exercise.targetMaxReps = action.parsedValue as int;\n          break;\n        case 'rest_seconds':")
text = text.replace("          exercise.restSeconds = action.parsedValue as int;\n        case 'notes':", "          exercise.restSeconds = action.parsedValue as int;\n          break;\n        case 'notes':")
text = text.replace("          exercise.notes = action.parsedValue as String;\n        default:", "          exercise.notes = action.parsedValue as String;\n          break;\n        default:")
path.write_text(text)

path = Path('lib/screens/ai_coach.dart')
text = path.read_text().replace('Icons.auto_awesome_motion_outlined', 'Icons.auto_awesome')
path.write_text(text)

# Remove an unused private compatibility helper before analyzer sees it.
path = Path('lib/app_data_store.dart')
text = path.read_text()
text = re.sub(
    r"\n  static WorkoutSession\? _safeLegacyCurrentSession\(SharedPreferences prefs\) \{.*?\n  \}\n",
    "\n",
    text,
    flags=re.S,
)
path.write_text(text)

# Migration test uses distinct historical and current-session IDs, matching runtime semantics.
path = Path('test/local_sqlite_store_test.dart')
text = path.read_text()
text = text.replace(
    "    final session = WorkoutSession(\n      id: 'session-1',",
    "    final session = WorkoutSession(\n      id: 'session-1',",
)
text = text.replace(
    "      currentSession: session,\n      bodyLogs: [body],",
    "      currentSession: _session('current-session', 81),\n      bodyLogs: [body],",
)
text = text.replace("    expect(data.currentSession?.id, 'session-1');", "    expect(data.currentSession?.id, 'current-session');")
path.write_text(text)
