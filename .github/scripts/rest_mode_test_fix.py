from pathlib import Path

ux_path = Path('test/workout_ux_polish_v2_test.dart')
ux = ux_path.read_text()
old_fab = "    expect(find.widgetWithText(FloatingActionButton, 'Esercizio'), findsNothing);\n"
new_fab = "    final restingScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);\n    expect(restingScaffold.floatingActionButton, isNull);\n"
if old_fab in ux:
    ux = ux.replace(old_fab, new_fab, 1)
elif 'expect(restingScaffold.floatingActionButton, isNull);' not in ux:
    raise SystemExit('rest FAB assertion anchor not found')

old_return = "    expect(find.widgetWithText(FloatingActionButton, 'Esercizio'), findsOneWidget);\n"
new_return = "    final idleScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);\n    expect(idleScaffold.floatingActionButton, isNotNull);\n"
if old_return in ux:
    ux = ux.replace(old_return, new_return, 1)
elif 'expect(idleScaffold.floatingActionButton, isNotNull);' not in ux:
    raise SystemExit('idle FAB assertion anchor not found')
ux_path.write_text(ux)

active_test_path = Path('test/active_workout_screen_test.dart')
active_test = active_test_path.read_text()
old_before = "    expect(find.textContaining('Recupero 01:'), findsNothing);\n"
new_before = "    expect(find.byKey(const ValueKey('rest-mode-drop_exercise')), findsNothing);\n"
if old_before in active_test:
    active_test = active_test.replace(old_before, new_before, 1)
elif "rest-mode-drop_exercise')), findsNothing" not in active_test:
    raise SystemExit('drop rest absent assertion anchor not found')
old_after = "    expect(find.textContaining('Recupero 01:'), findsOneWidget);\n"
new_after = "    expect(find.byKey(const ValueKey('rest-mode-drop_exercise')), findsOneWidget);\n    expect(find.byKey(const ValueKey('rest-workout-complete')), findsOneWidget);\n"
if old_after in active_test:
    active_test = active_test.replace(old_after, new_after, 1)
elif "rest-workout-complete')), findsOneWidget" not in active_test:
    raise SystemExit('drop rest present assertion anchor not found')
active_test_path.write_text(active_test)
