from pathlib import Path

home = Path('lib/screens/home.dart')
text = home.read_text()
text = text.replace(
    '_currentIndex = widget.initialIndex.clamp(0, 4);',
    '_currentIndex = widget.initialIndex.clamp(0, 4).toInt();',
)
text = text.replace('icon: Icon(Icons.list_alt_outlined),', 'icon: Icon(Icons.list_alt),')
text = text.replace(
    'icon: Icon(Icons.calendar_month_outlined),',
    'icon: Icon(Icons.calendar_month),',
)
text = text.replace(
    "  Widget build(BuildContext context) {\n    final theme = Theme.of(context);\n    final colorScheme = theme.colorScheme;\n    final isDark = theme.brightness == Brightness.dark;\n    final isCoach = _currentIndex == 4;",
    "  Widget build(BuildContext context) {\n    final theme = Theme.of(context);\n    final isDark = theme.brightness == Brightness.dark;\n    final isCoach = _currentIndex == 4;",
)
text = text.replace('child: NavigationBar(', 'child: BottomNavigationBar(')
text = text.replace(
    '                selectedIndex: _currentIndex,\n                onDestinationSelected: (index) {',
    '                type: BottomNavigationBarType.fixed,\n                currentIndex: _currentIndex,\n                showSelectedLabels: false,\n                showUnselectedLabels: false,\n                onTap: (index) {',
)
text = text.replace('                destinations: const [', '                items: const [')
text = text.replace('NavigationDestination(', 'BottomNavigationBarItem(')
text = text.replace('selectedIcon:', 'activeIcon:')
home.write_text(text)

test = Path('test/home_navigation_test.dart')
if test.exists():
    text = test.read_text()
    text = text.replace('find.byIcon(Icons.list_alt_outlined)', 'find.byIcon(Icons.list_alt)')
    text = text.replace(
        'find.byIcon(Icons.calendar_month_outlined)',
        'find.byIcon(Icons.calendar_month)',
    )
    text = text.replace("expect(find.text('Allenati'), findsOneWidget);", "expect(find.text('Allenati'), findsWidgets);")
    test.write_text(text)

legacy_test = Path('test/home_undo_test.dart')
text = legacy_test.read_text()
text = text.replace(
    "    expect(find.textContaining('Top set:'), findsNothing);\n\n    await tester.tap(find.byIcon(Icons.edit).first);",
    "    expect(find.textContaining('Top set:'), findsNothing);\n\n    await tester.ensureVisible(find.byIcon(Icons.edit).first);\n    await tester.pumpAndSettle();\n    await tester.tap(find.byIcon(Icons.edit).first);",
)
legacy_test.write_text(text)
