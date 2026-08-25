from pathlib import Path

home = Path('lib/screens/home.dart')
text = home.read_text()
text = text.replace(
    '_currentIndex = widget.initialIndex.clamp(0, 4);',
    '_currentIndex = widget.initialIndex.clamp(0, 4).toInt();',
)
text = text.replace(
    "  Widget build(BuildContext context) {\n    final theme = Theme.of(context);\n    final colorScheme = theme.colorScheme;\n    final isDark = theme.brightness == Brightness.dark;\n    final isCoach = _currentIndex == 4;",
    "  Widget build(BuildContext context) {\n    final theme = Theme.of(context);\n    final isDark = theme.brightness == Brightness.dark;\n    final isCoach = _currentIndex == 4;",
)

old_nav = '''              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() => _currentIndex = index);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.list_alt_outlined),
                    selectedIcon: Icon(Icons.list_alt),
                    label: 'Schede',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month),
                    label: 'Allenati',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history),
                    selectedIcon: Icon(Icons.insights),
                    label: 'Progressi',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.psychology_alt_outlined),
                    selectedIcon: Icon(Icons.psychology_alt),
                    label: 'Coach',
                  ),
                ],
              ),'''
new_nav = '''              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _currentIndex,
                showSelectedLabels: false,
                showUnselectedLabels: false,
                onTap: (index) {
                  setState(() => _currentIndex = index);
                },
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.list_alt),
                    activeIcon: Icon(Icons.list_alt),
                    label: 'Schede',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_month),
                    activeIcon: Icon(Icons.calendar_month),
                    label: 'Allenati',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.history),
                    activeIcon: Icon(Icons.insights),
                    label: 'Progressi',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.psychology_alt_outlined),
                    activeIcon: Icon(Icons.psychology_alt),
                    label: 'Coach',
                  ),
                ],
              ),'''
if old_nav not in text:
    raise RuntimeError('Unable to locate generated navigation block')
text = text.replace(old_nav, new_nav)
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
    "    expect(find.text('Progressi esercizi'), findsOneWidget);\n    expect(find.text('1 miglioramenti recenti'), findsOneWidget);\n\n    await tester.tap(find.text('Push').first);",
    "    expect(find.text('Progressi esercizi'), findsOneWidget);\n    expect(find.text('1 miglioramenti recenti'), findsOneWidget);\n\n    await tester.tap(find.text('Progressi esercizi'));\n    await tester.pumpAndSettle();\n    expect(find.text('Panca'), findsWidgets);\n    expect(find.textContaining('+80 kg'), findsOneWidget);\n    await tester.tap(find.text('Progressi esercizi'));\n    await tester.pumpAndSettle();\n\n    await tester.tap(find.text('Push').first);",
)
text = text.replace(
    "    expect(find.textContaining('Top set:'), findsNothing);\n\n    await tester.tap(find.byIcon(Icons.edit).first);",
    "    expect(find.textContaining('Top set:'), findsNothing);\n\n    await tester.ensureVisible(find.byIcon(Icons.edit).first);\n    await tester.pumpAndSettle();\n    await tester.tap(find.byIcon(Icons.edit).first);",
)
text = text.replace(
    "    await tester.tap(find.text('Annulla'));\n    await tester.pumpAndSettle();\n\n    await tester.tap(find.text('Progressi esercizi'));\n    await tester.pumpAndSettle();\n\n    expect(find.text('Panca'), findsWidgets);\n    expect(find.textContaining('+80 kg'), findsOneWidget);",
    "    await tester.tap(find.text('Annulla'));\n    await tester.pumpAndSettle();",
)
legacy_test.write_text(text)
