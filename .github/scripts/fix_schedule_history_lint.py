from pathlib import Path

path = Path('lib/app_data_store.dart')
text = path.read_text()
old = "        return _backfillScheduleHistory(bundle, persistSqlite: true);"
new = "        return await _backfillScheduleHistory(bundle, persistSqlite: true);"
if old not in text:
    raise SystemExit('schedule history async lint anchor not found')
path.write_text(text.replace(old, new, 1))
