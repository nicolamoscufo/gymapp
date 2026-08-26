from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:160]!r}')
    p.write_text(text.replace(old, new, 1))


replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "import 'ai_coach_memory.dart';\nimport 'program_history_context.dart';\n",
    "import 'ai_coach_memory.dart';\nimport 'program_change_effectiveness.dart';\nimport 'program_history_context.dart';\n",
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "      'program_history': buildProgramHistoryContext(\n        scheduleVersions: scheduleVersions,\n        history: fullHistory,\n        schedules: schedules,\n      ),\n      'workouts': workouts,\n",
    "      'program_history': buildProgramHistoryContext(\n        scheduleVersions: scheduleVersions,\n        history: fullHistory,\n        schedules: schedules,\n      ),\n      'program_change_effectiveness': buildProgramChangeEffectivenessContext(\n        scheduleVersions: scheduleVersions,\n        history: fullHistory,\n      ),\n      'workouts': workouts,\n",
)

replace_once(
    'lib/ai_coach/local_ai_coach_service.dart',
    "- When comparing program changes with later performance, distinguish exact linked evidence from unresolved legacy or orphaned-version history and state uncertainty when coverage is incomplete.\n",
    "- When comparing program changes with later performance, distinguish exact linked evidence from unresolved legacy or orphaned-version history and state uncertainty when coverage is incomplete.\n- Treat program_change_effectiveness as deterministic association evidence for adjacent program versions. Its improved/stable/declined/mixed statuses are authoritative calculations for the declared windows, but they never prove that the program change caused the outcome.\n- If program_change_effectiveness reports insufficient data, say that the effect cannot yet be evaluated instead of guessing.\n",
)
replace_once(
    'lib/ai_coach/local_ai_coach_service.dart',
    "Use program_history for longitudinal questions. Baselines plus ordered diffs reconstruct program evolution; version performance contains only workouts whose schedule_version_id resolves to a stored historical version. Treat null or orphaned version links as unresolved evidence and never infer their historical version.\n",
    "Use program_history for longitudinal questions. Baselines plus ordered diffs reconstruct program evolution; version performance contains only workouts whose schedule_version_id resolves to a stored historical version. Treat null or orphaned version links as unresolved evidence and never infer their historical version.\nUse program_change_effectiveness when discussing whether a reviewed program transition was followed by better, stable, worse, mixed, or insufficient outcomes. Treat it as deterministic association evidence, not causal proof, and preserve its uncertainty.\n",
)
