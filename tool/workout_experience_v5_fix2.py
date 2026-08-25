from pathlib import Path

# Home passes body logs into ScheduleDetail so every workout entry path can keep
# the same readiness context. The active workout can still reload them from the
# local store when needed.
schedule_path = Path('lib/screens/schedule_detail.dart')
schedule = schedule_path.read_text()
if "import '../models/body_log.dart';" not in schedule:
    schedule = schedule.replace(
        "import '../exercise_catalog.dart';",
        "import '../exercise_catalog.dart';\nimport '../models/body_log.dart';",
        1,
    )
if 'final List<BodyLog> bodyLogs;' not in schedule:
    schedule = schedule.replace(
        '  final List<WorkoutSession> history;\n',
        '  final List<WorkoutSession> history;\n  final List<BodyLog> bodyLogs;\n',
        1,
    )
if 'this.bodyLogs = const []' not in schedule:
    schedule = schedule.replace(
        '    this.history = const [],\n',
        '    this.history = const [],\n    this.bodyLogs = const [],\n',
        1,
    )
schedule_path.write_text(schedule)

# Strict analyze treats these style infos as fatal in this repository.
fatigue_path = Path('lib/workout_fatigue_analytics.dart')
fatigue = fatigue_path.read_text().replace(
    '(${selfReadiness}/10)',
    '($selfReadiness/10)',
)
fatigue_path.write_text(fatigue)

# Keep the widget-test RPE value explicitly double.
test_path = Path('test/workout_experience_v5_test.dart')
test = test_path.read_text().replace(
    'rpe: rir == 0 ? 10 : 10 - rir,',
    'rpe: rir == 0 ? 10.0 : (10 - rir).toDouble(),',
)
test_path.write_text(test)
