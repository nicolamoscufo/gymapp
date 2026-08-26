from pathlib import Path

path = Path('lib/progress_period_comparison.dart')
text = path.read_text()
replacements = {
    "int get durationDays => math.max(1, endExclusive.difference(start).inDays);":
        "int get durationDays => math.max(1, endExclusive.difference(start).inDays).toInt();",
    "final cycleDays = math.max(1, schedule.mesocycleWeeks) * 7;":
        "final cycleDays = math.max(1, schedule.mesocycleWeeks).toInt() * 7;",
    "final elapsedDays = math.max(1, currentEnd.difference(cycleStart).inDays);":
        "final elapsedDays = math.max(1, currentEnd.difference(cycleStart).inDays).toInt();",
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'missing anchor: {old}')
    text = text.replace(old, new, 1)
path.write_text(text)
