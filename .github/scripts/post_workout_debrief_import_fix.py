from pathlib import Path

path = Path('lib/screens/session_summary.dart')
text = path.read_text()
needle = "import '../post_workout_debrief.dart';\n"
if needle not in text:
    raise SystemExit('post workout import not found')
text = text.replace(
    needle,
    needle + "import '../workout_progression_analytics.dart';\n",
    1,
)
path.write_text(text)
