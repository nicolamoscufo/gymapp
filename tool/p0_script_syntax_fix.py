from pathlib import Path

path = Path('tool/p0_patch.py')
text = path.read_text()
start = "Path('lib/local_sqlite_store.dart').write_text(r'''import 'dart:convert';"
marker = "\n''')\n\n# Replace AppDataStore with a SQLite-first facade plus legacy migration/fallback."
if start not in text or marker not in text:
    raise RuntimeError('local sqlite patch block anchors not found')
text = text.replace(
    start,
    'Path(\'lib/local_sqlite_store.dart\').write_text(r"""import \'dart:convert\';',
    1,
)
text = text.replace(
    marker,
    '\n""")\n\n# Replace AppDataStore with a SQLite-first facade plus legacy migration/fallback.',
    1,
)
path.write_text(text)
