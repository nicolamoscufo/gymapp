from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_between(
    text: str,
    start: str,
    end: str,
    replacement: str,
    label: str,
) -> str:
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError(f"{label}: start marker not found: {start!r}")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise RuntimeError(f"{label}: end marker not found: {end!r}")
    return text[:start_index] + replacement + text[end_index:]


def migrate_active_workout() -> tuple[int, int]:
    path = ROOT / "lib/screens/active_workout.dart"
    text = path.read_text()
    before = len(text.splitlines())

    text = replace_once(
        text,
        "import '../active_workout_exercise_manager.dart';\n",
        "import '../active_workout_exercise_manager.dart';\n"
        "import '../active_workout_focus_controller.dart';\n",
        "active focus import",
    )
    text = replace_once(
        text,
        "import '../ui/workout_components.dart';\n",
        "import '../ui/active_workout_input_components.dart';\n"
        "import '../ui/workout_components.dart';\n",
        "active input component import",
    )

    text = replace_once(
        text,
        "  final Map<String, GlobalKey> _exerciseCardKeys = {};\n"
        "  final Map<String, GlobalKey> _setRowKeys = {};\n"
        "  final ScrollController _workoutScrollController = ScrollController();\n"
        "  String? _focusedExerciseId;\n",
        "  final ActiveWorkoutFocusController _focusController =\n"
        "      ActiveWorkoutFocusController();\n"
        "  String? get _focusedExerciseId => _focusController.focusedExerciseId;\n"
        "  set _focusedExerciseId(String? value) =>\n"
        "      _focusController.focusedExerciseId = value;\n",
        "active focus fields",
    )

    text = replace_between(
        text,
        "  GlobalKey _exerciseCardKey(String exerciseId) {",
        "  bool _isExerciseComplete",
        "  GlobalKey _exerciseCardKey(String exerciseId) =>\n"
        "      _focusController.exerciseCardKey(exerciseId);\n\n"
        "  GlobalKey _setRowKey(String setId) => _focusController.setRowKey(setId);\n\n"
        "  String? _effectiveFocusedExerciseId() =>\n"
        "      _focusController.effectiveFocusedExerciseId(\n"
        "        session.exercises,\n"
        "        editCompletedSession: widget.editCompletedSession,\n"
        "      );\n\n",
        "active focus helpers",
    )

    text = replace_between(
        text,
        "  Future<void> _scrollToSet(String exerciseId, String setId) async {",
        "  void _selectExerciseFromJumpBar",
        "  Future<void> _scrollToSet(String exerciseId, String setId) {\n"
        "    return _focusController.scrollToSet(\n"
        "      exercises: session.exercises,\n"
        "      exerciseId: exerciseId,\n"
        "      setId: setId,\n"
        "    );\n"
        "  }\n\n"
        "  void _scrollToExercise(String exerciseId) =>\n"
        "      _focusController.scrollToExercise(exerciseId);\n\n",
        "active scroll helpers",
    )

    text = text.replace(
        "_exerciseCardKeys.remove(exercise.id);",
        "_focusController.removeExercise(exercise.id);",
    )
    text = text.replace(
        "_workoutScrollController",
        "_focusController.scrollController",
    )
    text = text.replace(
        "_focusController.scrollController.dispose();",
        "_focusController.dispose();",
    )

    private_widget_marker = "\nclass _ExerciseJumpBar extends StatelessWidget {"
    marker_index = text.find(private_widget_marker)
    if marker_index < 0:
        raise RuntimeError("active private widget marker not found")
    text = text[:marker_index] + "\n"
    text = text.replace("_ExerciseJumpBar(", "WorkoutExerciseJumpBar(")
    text = text.replace("_StableSetTextField(", "StableWorkoutSetTextField(")

    forbidden = [
        "_exerciseCardKeys",
        "_setRowKeys",
        "_workoutScrollController",
        "class _ExerciseJumpBar",
        "class _StableSetTextField",
    ]
    for token in forbidden:
        if token in text:
            raise RuntimeError(f"active migration left forbidden token {token!r}")

    path.write_text(text)
    return before, len(text.splitlines())


def migrate_home() -> tuple[int, int]:
    path = ROOT / "lib/screens/home.dart"
    text = path.read_text()
    before = len(text.splitlines())

    text = replace_once(
        text,
        "import '../home_data_policy.dart';\n",
        "import '../home_data_policy.dart';\n"
        "import '../home_dashboard_state.dart';\n"
        "import '../home_history_analytics.dart';\n",
        "home architecture imports",
    )
    text = replace_once(
        text,
        "enum _HistoryRangeFilter { all, last30, last90 }\n\n",
        "",
        "home history enum",
    )
    text = text.replace("_HistoryRangeFilter", "HomeHistoryRangeFilter")

    text = replace_between(
        text,
        "  String _normalizeExerciseName(String name)",
        "  WorkoutExercise? _previousExerciseBefore",
        "  double _exerciseVolume(WorkoutExercise exercise) =>\n"
        "      HomeHistoryAnalytics(history).exerciseVolume(exercise);\n\n"
        "  double _bestSetVolume(WorkoutExercise exercise) =>\n"
        "      HomeHistoryAnalytics(history).bestSetVolume(exercise);\n\n",
        "home volume analytics",
    )
    text = replace_between(
        text,
        "  WorkoutExercise? _previousExerciseBefore(",
        "  bool _exerciseHasPrAtSession",
        "  WorkoutExercise? _previousExerciseBefore(\n"
        "    WorkoutSession session,\n"
        "    WorkoutExercise exercise,\n"
        "  ) => HomeHistoryAnalytics(history).previousExerciseBefore(\n"
        "    session,\n"
        "    exercise,\n"
        "  );\n\n",
        "home previous exercise analytics",
    )
    text = replace_between(
        text,
        "  bool _exerciseHasPrAtSession(",
        "  bool _sessionHasPr",
        "  bool _exerciseHasPrAtSession(\n"
        "    WorkoutSession session,\n"
        "    WorkoutExercise exercise,\n"
        "  ) => HomeHistoryAnalytics(history).exerciseHasPrAtSession(\n"
        "    session,\n"
        "    exercise,\n"
        "  );\n\n",
        "home exercise PR analytics",
    )
    text = replace_between(
        text,
        "  bool _sessionHasPr(WorkoutSession session)",
        "  List<WorkoutSession> _filteredHistorySessions",
        "  bool _sessionHasPr(WorkoutSession session) =>\n"
        "      HomeHistoryAnalytics(history).sessionHasPr(session);\n\n",
        "home session PR analytics",
    )
    text = replace_between(
        text,
        "  List<WorkoutSession> _filteredHistorySessions(",
        "  List<_PrSummary> _buildRecentPrSummaries",
        "  List<WorkoutSession> _filteredHistorySessions(\n"
        "    List<WorkoutSession> sortedHistory,\n"
        "  ) => HomeHistoryAnalytics(history).filteredSessions(\n"
        "    sortedHistory,\n"
        "    range: _historyRangeFilter,\n"
        "    query: _historyQuery,\n"
        "    onlyPr: _historyOnlyPr,\n"
        "  );\n\n",
        "home history filtering",
    )
    text = replace_between(
        text,
        "  List<_PrSummary> _buildRecentPrSummaries()",
        "  Widget _buildHistoryFilterCard",
        "  List<HomePrSummary> _buildRecentPrSummaries() =>\n"
        "      HomeHistoryAnalytics(history).buildRecentPrSummaries();\n\n",
        "home PR summaries",
    )
    text = replace_between(
        text,
        "  List<_ExerciseProgressSummary> _buildExerciseProgressSummaries()",
        "  Widget _buildExerciseProgressCard",
        "  List<HomeExerciseProgressSummary> _buildExerciseProgressSummaries() =>\n"
        "      HomeHistoryAnalytics(history).buildExerciseProgressSummaries();\n\n",
        "home progress summaries",
    )

    text = replace_between(
        text,
        "  bool _sameDay(DateTime a, DateTime b)",
        "  _PlannedWorkout? _nextPlannedWorkout",
        "  bool _sameDay(DateTime a, DateTime b) =>\n"
        "      HomeDashboardState.sameDay(a, b);\n\n",
        "home same-day state",
    )
    text = replace_between(
        text,
        "  _PlannedWorkout? _nextPlannedWorkout()",
        "  int _workoutsThisWeek",
        "  HomePlannedWorkout? _nextPlannedWorkout() =>\n"
        "      HomeDashboardState.nextPlannedWorkout(schedules);\n\n",
        "home planned workout state",
    )
    text = replace_between(
        text,
        "  int _workoutsThisWeek()",
        "  BodyLog? _latestBodyLog",
        "  int _workoutsThisWeek() =>\n"
        "      HomeDashboardState.workoutsThisWeek(history);\n\n",
        "home weekly state",
    )
    text = replace_between(
        text,
        "  BodyLog? _latestBodyLog()",
        "  Future<void> _startScheduleFromHome",
        "  BodyLog? _latestBodyLog() => HomeDashboardState.latestBodyLog(bodyLogs);\n\n",
        "home latest body state",
    )

    bottom_start = text.find("\nclass _PlannedWorkout {")
    bottom_end = text.find("\nclass _BackupMergeResult {", bottom_start)
    if bottom_start < 0 or bottom_end < 0:
        raise RuntimeError("home derived-class block markers not found")
    text = text[:bottom_start] + text[bottom_end:]

    text = text.replace("_PrSummary", "HomePrSummary")
    text = text.replace("_ExerciseProgressSummary", "HomeExerciseProgressSummary")

    forbidden = [
        "_HistoryRangeFilter",
        "_ExerciseOccurrence",
        "class _ExerciseProgressSummary",
        "class _PrSummary",
        "class _PlannedWorkout",
        "_normalizeExerciseName",
        "_completedWorkSets",
    ]
    for token in forbidden:
        if token in text:
            raise RuntimeError(f"home migration left forbidden token {token!r}")

    path.write_text(text)
    return before, len(text.splitlines())


def main() -> None:
    active_before, active_after = migrate_active_workout()
    home_before, home_after = migrate_home()
    print(
        f"active_workout.dart: {active_before} -> {active_after} lines "
        f"({active_before - active_after} removed)"
    )
    print(
        f"home.dart: {home_before} -> {home_after} lines "
        f"({home_before - home_after} removed)"
    )
    if active_after >= active_before or home_after >= home_before:
        raise RuntimeError("screen refactor did not reduce both monoliths")


if __name__ == "__main__":
    main()
