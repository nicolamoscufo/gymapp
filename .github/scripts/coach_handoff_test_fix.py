from pathlib import Path

path = Path('test/ai_coach_handoff_test.dart')
text = path.read_text()
old = "    await tester.tap(button);\n    await tester.pump();\n"
new = "    final coachButton = tester.widget<FilledButton>(button);\n    coachButton.onPressed!.call();\n    await tester.pump();\n    await tester.pump(const Duration(milliseconds: 350));\n"
if old not in text:
    raise SystemExit('navigation timing target not found')
path.write_text(text.replace(old, new, 1))
