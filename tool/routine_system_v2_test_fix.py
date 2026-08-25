from pathlib import Path

path = Path('test/routine_system_v2_test.dart')
text = path.read_text()
old = "    await tester.tap(find.text('Cartella'));\n"
new = "    await tester.tap(find.widgetWithText(ListTile, 'Cartella'));\n"
if old not in text:
    raise RuntimeError('Routine v2 folder test anchor not found')
path.write_text(text.replace(old, new, 1))
