from pathlib import Path

path = Path('test/home_undo_test.dart')
text = path.read_text()

old_rest = """    expect(find.textContaining('Rest 00:'), findsOneWidget);\n    expect(find.textContaining('Recupero 00:'), findsOneWidget);\n    expect(find.text('Salta'), findsOneWidget);\n"""
new_rest = """    expect(\n      find.byKey(const ValueKey('rest-mode-countdown')),\n      findsOneWidget,\n    );\n    expect(find.text('Salta'), findsOneWidget);\n"""
if old_rest not in text:
    raise SystemExit('legacy rest expectations not found')
text = text.replace(old_rest, new_rest, 1)

old_pr = """    await tester.enterText(find.byType(TextFormField).at(2), '80');\n    await tester.tap(find.byIcon(Icons.check).last);\n    await tester.pump();\n\n    expect(find.byIcon(Icons.emoji_events), findsWidgets);\n"""
new_pr = """    await tester.enterText(find.byType(TextFormField).at(2), '80');\n    final completeSetButton = find.byWidgetPredicate((widget) {\n      final key = widget.key;\n      return key is ValueKey<String> &&\n          key.value.startsWith('thumb-complete-');\n    });\n    expect(completeSetButton, findsOneWidget);\n    await tester.ensureVisible(completeSetButton);\n    await tester.tap(completeSetButton);\n    await tester.pump();\n\n    expect(find.byIcon(Icons.emoji_events), findsWidgets);\n"""
if old_pr not in text:
    raise SystemExit('legacy PR completion interaction not found')
text = text.replace(old_pr, new_pr, 1)

path.write_text(text)
