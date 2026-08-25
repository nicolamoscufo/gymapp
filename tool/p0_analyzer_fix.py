from pathlib import Path

path = Path('lib/ai_coach/ai_plan_action_service.dart')
text = path.read_text()
text = text.replace(
    "    Exercise? exercise;\n    if (action.exerciseId.isNotEmpty) {",
    "    if (action.exerciseId.isNotEmpty) {",
)
text = text.replace(
    "        return numeric == null ? null : numeric.round();",
    "        return numeric?.round();",
)
path.write_text(text)
