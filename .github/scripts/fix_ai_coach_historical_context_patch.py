from pathlib import Path

path = Path('.github/scripts/add_ai_coach_historical_context.py')
text = path.read_text()
old = '''replace_all(
    'lib/ai_coach/training_context_builder.dart',
    "      schedules: schedules,\\n      bodyLogs: bodyLogs,\\n",
    "      schedules: schedules,\\n      scheduleVersions: scheduleVersions,\\n      bodyLogs: bodyLogs,\\n",
    expected=4,
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "    required List<WorkoutSession> analyticsHistory,\\n    required List<Schedule> schedules,\\n",
'''
new = '''replace_all(
    'lib/ai_coach/training_context_builder.dart',
    "      schedules: schedules,\\n      bodyLogs: bodyLogs,\\n",
    "      schedules: schedules,\\n      scheduleVersions: scheduleVersions,\\n      bodyLogs: bodyLogs,\\n",
    expected=3,
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "    schedules: schedules,\\n    bodyLogs: bodyLogs,\\n    profile: profile,\\n",
    "    schedules: schedules,\\n    scheduleVersions: scheduleVersions,\\n    bodyLogs: bodyLogs,\\n    profile: profile,\\n",
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "    required List<WorkoutSession> analyticsHistory,\\n    required List<Schedule> schedules,\\n",
'''
if old not in text:
    raise SystemExit('historical context schedules anchor not found')
path.write_text(text.replace(old, new, 1))
