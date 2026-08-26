from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:140]!r}')
    p.write_text(text.replace(old, new, 1))


def replace_all(path, old, new, expected=None):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if expected is not None and count != expected:
        raise SystemExit(f'expected {expected} anchors in {path}, found {count}: {old[:120]!r}')
    if count == 0:
        raise SystemExit(f'anchor not found in {path}: {old[:140]!r}')
    p.write_text(text.replace(old, new))


# TrainingContextBuilder: retain scoped raw detail but always add complete,
# deterministic program history built from the full workout history.
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "import '../models/schedule.dart';\n",
    "import '../models/schedule.dart';\nimport '../models/schedule_version.dart';\n",
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "import 'ai_coach_memory.dart';\n",
    "import 'ai_coach_memory.dart';\nimport 'program_history_context.dart';\n",
)
replace_all(
    'lib/ai_coach/training_context_builder.dart',
    "    required List<Schedule> schedules,\n    List<BodyLog> bodyLogs = const [],\n",
    "    required List<Schedule> schedules,\n    List<ScheduleVersion> scheduleVersions = const [],\n    List<BodyLog> bodyLogs = const [],\n",
    expected=4,
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "      history: latest,\n      analyticsHistory: sorted,\n",
    "      history: latest,\n      analyticsHistory: sorted,\n      fullHistory: sorted,\n",
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "      history: weeklyHistory,\n      analyticsHistory: weeklyHistory,\n",
    "      history: weeklyHistory,\n      analyticsHistory: weeklyHistory,\n      fullHistory: history,\n",
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "      history: recentHistory,\n      analyticsHistory: recentHistory,\n",
    "      history: recentHistory,\n      analyticsHistory: recentHistory,\n      fullHistory: history,\n",
)
replace_all(
    'lib/ai_coach/training_context_builder.dart',
    "      schedules: schedules,\n      bodyLogs: bodyLogs,\n",
    "      schedules: schedules,\n      scheduleVersions: scheduleVersions,\n      bodyLogs: bodyLogs,\n",
    expected=4,
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "    required List<WorkoutSession> analyticsHistory,\n    required List<Schedule> schedules,\n",
    "    required List<WorkoutSession> analyticsHistory,\n    required List<WorkoutSession> fullHistory,\n    required List<Schedule> schedules,\n    required List<ScheduleVersion> scheduleVersions,\n",
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "      'active_plans': activePlans,\n      'workouts': workouts,\n",
    "      'active_plans': activePlans,\n      'program_history': buildProgramHistoryContext(\n        scheduleVersions: scheduleVersions,\n        history: fullHistory,\n        schedules: schedules,\n      ),\n      'workouts': workouts,\n",
)
replace_once(
    'lib/ai_coach/training_context_builder.dart',
    "    'id': session.id,\n    'name': session.scheduleTitle,\n",
    "    'id': session.id,\n    'schedule_id': session.scheduleId,\n    'schedule_version_id': session.scheduleVersionId,\n    'name': session.scheduleTitle,\n",
)

# Service: make historical versions first-class context for every Coach task.
replace_once(
    'lib/ai_coach/local_ai_coach_service.dart',
    "import '../models/schedule.dart';\n",
    "import '../models/schedule.dart';\nimport '../models/schedule_version.dart';\n",
)
replace_all(
    'lib/ai_coach/local_ai_coach_service.dart',
    "    required List<Schedule> schedules,\n    List<BodyLog> bodyLogs = const [],\n",
    "    required List<Schedule> schedules,\n    List<ScheduleVersion> scheduleVersions = const [],\n    List<BodyLog> bodyLogs = const [],\n",
    expected=7,
)
replace_all(
    'lib/ai_coach/local_ai_coach_service.dart',
    "      schedules: schedules,\n      bodyLogs: bodyLogs,\n",
    "      schedules: schedules,\n      scheduleVersions: scheduleVersions,\n      bodyLogs: bodyLogs,\n",
    expected=7,
)
replace_once(
    'lib/ai_coach/local_ai_coach_service.dart',
    "- Use the provided training context to give personalized advice.\n",
    "- Use the provided training context to give personalized advice.\n- Treat program_history as a deterministic longitudinal record: exact schedule_version_id links are authoritative.\n- Never assign a workout with a null schedule_version_id to a historical version by guess, title similarity, date proximity, or exercise similarity.\n- When comparing program changes with later performance, distinguish exact linked evidence from unresolved legacy history and state uncertainty when coverage is incomplete.\n",
)
replace_once(
    'lib/ai_coach/local_ai_coach_service.dart',
    "If focus_context exists, it is the authoritative scope for the current discussion: use the exact target session and deterministic debrief values first, then enrich the explanation with the broader training context. Do not contradict deterministic metrics or recommendations without explicitly explaining the evidence and uncertainty.\n",
    "If focus_context exists, it is the authoritative scope for the current discussion: use the exact target session and deterministic debrief values first, then enrich the explanation with the broader training context. Do not contradict deterministic metrics or recommendations without explicitly explaining the evidence and uncertainty.\nUse program_history for longitudinal questions. Baselines plus ordered diffs reconstruct program evolution; version performance contains only workouts with exact version links. Never infer a missing legacy link.\n",
)

# Screen and entry: pass the versions already loaded in AppDataBundle, avoiding
# extra persistence reads for each message.
replace_once(
    'lib/screens/ai_coach.dart',
    "  final List<Schedule> schedules;\n  final List<BodyLog> bodyLogs;\n",
    "  final List<Schedule> schedules;\n  final List<ScheduleVersion> scheduleVersions;\n  final List<BodyLog> bodyLogs;\n",
)
replace_once(
    'lib/screens/ai_coach.dart',
    "    required this.schedules,\n    this.bodyLogs = const [],\n",
    "    required this.schedules,\n    this.scheduleVersions = const [],\n    this.bodyLogs = const [],\n",
)
replace_all(
    'lib/screens/ai_coach.dart',
    "        schedules: widget.schedules,\n        bodyLogs: widget.bodyLogs,\n",
    "        schedules: widget.schedules,\n        scheduleVersions: widget.scheduleVersions,\n        bodyLogs: widget.bodyLogs,\n",
    expected=2,
)
replace_once(
    'lib/screens/ai_coach_entry.dart',
    "          schedules: bundle.schedules,\n          bodyLogs: bundle.bodyLogs,\n",
    "          schedules: bundle.schedules,\n          scheduleVersions: bundle.scheduleVersions,\n          bodyLogs: bundle.bodyLogs,\n",
)

# Test doubles must accept the new optional named argument to preserve the
# LocalAiCoachService interface contract.
for path, expected in [
    ('test/ai_coach_test.dart', 2),
    ('test/ai_coach_handoff_test.dart', 1),
]:
    replace_once(
        path,
        "import 'package:gymapp/models/schedule.dart';\n",
        "import 'package:gymapp/models/schedule.dart';\nimport 'package:gymapp/models/schedule_version.dart';\n",
    )
    replace_all(
        path,
        "    required List<Schedule> schedules,\n    List<BodyLog> bodyLogs = const [],\n",
        "    required List<Schedule> schedules,\n    List<ScheduleVersion> scheduleVersions = const [],\n    List<BodyLog> bodyLogs = const [],\n",
        expected=expected,
    )
