from pathlib import Path

path = Path('test/home_undo_test.dart')
text = path.read_text()
old = "expect(payload['version'], 5);"
new = "expect(payload['version'], 6);"
if old not in text:
    raise SystemExit('backup version expectation anchor not found')
path.write_text(text.replace(old, new, 1))
