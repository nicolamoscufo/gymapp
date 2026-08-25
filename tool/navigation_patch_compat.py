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
home.write_text(text)

test = Path('test/home_navigation_test.dart')
if test.exists():
    text = test.read_text()
    text = text.replace('find.byIcon(Icons.list_alt_outlined)', 'find.byIcon(Icons.list_alt)')
    text = text.replace(
        'find.byIcon(Icons.calendar_month_outlined)',
        'find.byIcon(Icons.calendar_month)',
    )
    test.write_text(text)
