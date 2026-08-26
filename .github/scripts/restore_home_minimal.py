from pathlib import Path
import subprocess

base = subprocess.check_output(
    ['git', 'show', 'origin/main:lib/screens/home.dart'],
    text=True,
)
old = 'ProgressCenterScreen(history: history),'
new = 'ProgressCenterScreen(history: history, schedules: schedules),'
if old not in base:
    raise SystemExit('ProgressCenterScreen anchor not found in main home')
Path('lib/screens/home.dart').write_text(base.replace(old, new, 1))
