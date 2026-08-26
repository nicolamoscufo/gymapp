from pathlib import Path

path = Path('.github/scripts/add_schedule_history_backup_restore.py')
text = path.read_text()
old = """          await db.execute('''
            CREATE TABLE workout_sessions (
              id TEXT PRIMARY KEY,
              session_kind TEXT NOT NULL,
              position INTEGER NOT NULL,
              schedule_id TEXT,
              schedule_title TEXT NOT NULL,
              start_time TEXT NOT NULL,
              end_time TEXT NOT NULL
            )
          ''');"""
new = """          await db.execute(
            'CREATE TABLE workout_sessions (id TEXT PRIMARY KEY, session_kind TEXT NOT NULL, position INTEGER NOT NULL, schedule_id TEXT, schedule_title TEXT NOT NULL, start_time TEXT NOT NULL, end_time TEXT NOT NULL)',
          );"""
if old not in text:
    raise SystemExit('backup patch SQL quoting anchor not found')
path.write_text(text.replace(old, new, 1))
