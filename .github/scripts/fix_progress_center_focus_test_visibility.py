from pathlib import Path

path = Path('test/progress_center_test.dart')
text = path.read_text()
old = """      expect(find.text('Progress Intelligence'), findsOneWidget);\n      expect(find.text('Da monitorare'), findsOneWidget);\n      expect(find.text('Momentum esercizi'), findsOneWidget);\n      expect(find.text('Esposizione muscolare'), findsOneWidget);\n      expect(find.byKey(const ValueKey('progress-pr-momentum')), findsOneWidget);\n      expect(find.byKey(const ValueKey('progress-focus-Panca')), findsOneWidget);\n"""
new = """      expect(find.text('Progress Intelligence'), findsOneWidget);\n      expect(find.text('Da monitorare'), findsOneWidget);\n      expect(find.text('Momentum esercizi'), findsOneWidget);\n      expect(find.byKey(const ValueKey('progress-pr-momentum')), findsOneWidget);\n      expect(find.byKey(const ValueKey('progress-focus-Panca')), findsOneWidget);\n\n      final focusList = find.byType(ListView).last;\n      for (\n        var i = 0;\n        i < 3 && find.text('Esposizione muscolare').evaluate().isEmpty;\n        i++\n      ) {\n        await tester.drag(focusList, const Offset(0, -350));\n        await tester.pumpAndSettle();\n      }\n      expect(find.text('Esposizione muscolare'), findsOneWidget);\n"""
if old not in text:
    raise SystemExit('focus expectations block not found')
path.write_text(text.replace(old, new, 1))
