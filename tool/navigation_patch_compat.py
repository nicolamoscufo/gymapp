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
