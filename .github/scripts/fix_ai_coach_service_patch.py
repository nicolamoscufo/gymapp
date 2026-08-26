from pathlib import Path

path = Path('.github/scripts/add_ai_coach_historical_context.py')
text = path.read_text()

old = '''replace_all(
    'lib/ai_coach/local_ai_coach_service.dart',
    "    required List<Schedule> schedules,\\n    List<BodyLog> bodyLogs = const [],\\n",
    "    required List<Schedule> schedules,\\n    List<ScheduleVersion> scheduleVersions = const [],\\n    List<BodyLog> bodyLogs = const [],\\n",
    expected=7,
)
replace_all(
    'lib/ai_coach/local_ai_coach_service.dart',
'''
new = '''replace_all(
    'lib/ai_coach/local_ai_coach_service.dart',
    "    required List<Schedule> schedules,\\n    List<BodyLog> bodyLogs = const [],\\n",
    "    required List<Schedule> schedules,\\n    List<ScheduleVersion> scheduleVersions = const [],\\n    List<BodyLog> bodyLogs = const [],\\n",
    expected=5,
)
replace_once(
    'lib/ai_coach/local_ai_coach_service.dart',
    "    required List<Schedule> schedules,\\n    required List<AiCoachImageInput> images,\\n    List<BodyLog> bodyLogs = const [],\\n",
    "    required List<Schedule> schedules,\\n    required List<AiCoachImageInput> images,\\n    List<ScheduleVersion> scheduleVersions = const [],\\n    List<BodyLog> bodyLogs = const [],\\n",
)
replace_once(
    'lib/ai_coach/local_ai_coach_service.dart',
    "    required List<Schedule> schedules,\\n    required List<ChatMessage> messages,\\n    List<BodyLog> bodyLogs = const [],\\n",
    "    required List<Schedule> schedules,\\n    required List<ChatMessage> messages,\\n    List<ScheduleVersion> scheduleVersions = const [],\\n    List<BodyLog> bodyLogs = const [],\\n",
)
replace_all(
    'lib/ai_coach/local_ai_coach_service.dart',
'''
if old not in text:
    raise SystemExit('service signature patch block not found')
text = text.replace(old, new, 1)

old = '''for path, expected in [
    ('test/ai_coach_test.dart', 2),
    ('test/ai_coach_handoff_test.dart', 1),
]:'''
new = '''for path, expected in [
    ('test/ai_coach_test.dart', 2),
]:'''
if old not in text:
    raise SystemExit('test double loop block not found')
text = text.replace(old, new, 1)

text += '''\n# Handoff fake has required messages between schedules and optional context.\nreplace_once(\n    'test/ai_coach_handoff_test.dart',\n    "import 'package:gymapp/models/schedule.dart';\\n",\n    "import 'package:gymapp/models/schedule.dart';\\nimport 'package:gymapp/models/schedule_version.dart';\\n",\n)\nreplace_once(\n    'test/ai_coach_handoff_test.dart',\n    "    required List<Schedule> schedules,\\n    required List<ChatMessage> messages,\\n    List<BodyLog> bodyLogs = const [],\\n",\n    "    required List<Schedule> schedules,\\n    required List<ChatMessage> messages,\\n    List<ScheduleVersion> scheduleVersions = const [],\\n    List<BodyLog> bodyLogs = const [],\\n",\n)\n'''

path.write_text(text)
