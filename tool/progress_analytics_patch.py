from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'anchor not found: {label}')
    return text.replace(old, new, 1)


home_path = Path('lib/screens/home.dart')
home = home_path.read_text()
home = replace_once(
    home,
    "import 'stats.dart';",
    "import 'progress_center.dart';",
    'home stats import',
)
home = replace_once(
    home,
    'StatsScreen(history: history),',
    'ProgressCenterScreen(history: history),',
    'home progress center route',
)
home_path.write_text(home)

context_path = Path('lib/ai_coach/training_context_builder.dart')
context = context_path.read_text()
context = replace_once(
    context,
    "import '../models/workout.dart';\n",
    "import '../models/workout.dart';\nimport '../progress_analytics.dart';\n",
    'progress analytics import',
)
context = replace_once(
    context,
    "      'deterministic_analytics': {\n        'exercise_progress': _exerciseProgress(history),",
    "      'deterministic_analytics': {\n        'progress_analytics': buildProgressAnalytics(\n          history: analyticsHistory,\n          now: _now,\n        ).toJson(),\n        'exercise_progress': _exerciseProgress(history),",
    'progress analytics context',
)
context_path.write_text(context)

prompt_path = Path('lib/ai_coach/ai_coach_prompts.dart')
prompt = prompt_path.read_text()
prompt = replace_once(
    prompt,
    '- deterministic_analytics.progression_recommendations is the source of truth for increaseLoad, increaseReps, maintain, deload, or manual decisions when present. You may explain the decision and its uncertainty, but do not output a conflicting progression action.\n',
    '- deterministic_analytics.progression_recommendations is the source of truth for increaseLoad, increaseReps, maintain, deload, or manual decisions when present. You may explain the decision and its uncertainty, but do not output a conflicting progression action.\n- deterministic_analytics.progress_analytics is the source of truth for PR counts, exercise e1RM/volume trends, muscle-group set distribution, consistency streaks, monthly reports and year summaries. Never invent or recalculate conflicting values.\n',
    'progress analytics prompt grounding',
)
prompt_path.write_text(prompt)
