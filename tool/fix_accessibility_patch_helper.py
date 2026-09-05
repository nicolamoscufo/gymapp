from pathlib import Path

# Correct the one overly strict patch precondition.
path = Path('tool/patch_accessibility_one_hand_ux.py')
text = path.read_text()
old = 'assert s.count(needle) >= 2\ns = s.replace(needle, replacement, 1)'
new = 'assert s.count(needle) >= 1\ns = s.replace(needle, replacement, 1)'
assert text.count(old) == 1
path.write_text(text.replace(old, new, 1))

# SemanticsHandle must be disposed before Flutter's end-of-test verification,
# and the narrow horizontal jump bar should assert its visible first item.
path = Path('test/accessibility_one_hand_ux_test.dart')
text = path.read_text()
text = text.replace(
    '    final semantics = tester.ensureSemantics();\n    addTearDown(semantics.dispose);\n',
    '    final semantics = tester.ensureSemantics();\n',
)

old = """    expect(rowSemantics.getSemanticsData().customSemanticsActionIds, isNotEmpty);\n  });\n"""
new = """    expect(rowSemantics.getSemanticsData().customSemanticsActionIds, isNotEmpty);\n    semantics.dispose();\n  });\n"""
assert text.count(old) == 1
text = text.replace(old, new, 1)

old = """    expect(find.bySemanticsLabel('Salta il recupero'), findsOneWidget);\n  });\n"""
new = """    expect(find.bySemanticsLabel('Salta il recupero'), findsOneWidget);\n    semantics.dispose();\n  });\n"""
assert text.count(old) == 1
text = text.replace(old, new, 1)

text = text.replace(
    "find.bySemanticsLabel('Vai a Rematore con manubrio')",
    "find.bySemanticsLabel('Vai a Panca piana con bilanciere')",
    1,
)
old = """      findsOneWidget,\n    );\n  });\n}\n"""
new = """      findsOneWidget,\n    );\n    semantics.dispose();\n  });\n}\n"""
assert text.count(old) >= 1
text = text.rsplit(old, 1)[0] + new
path.write_text(text)
