from pathlib import Path

path = Path('test/schedule_version_history_test.dart')
text = path.read_text()
old = "        weight: 80,\n        muscleGroup: MuscleGroup.chest,\n      ),"
new = "        weight: 80,\n        muscleGroup: MuscleGroup.chest,\n        technique: IntensityTechnique.none,\n      ),"
if old not in text:
    raise SystemExit('schedule history test fixture anchor not found')
path.write_text(text.replace(old, new, 1))
