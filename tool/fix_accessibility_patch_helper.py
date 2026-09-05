from pathlib import Path

path = Path('tool/patch_accessibility_one_hand_ux.py')
text = path.read_text()
old = 'assert s.count(needle) >= 2\ns = s.replace(needle, replacement, 1)'
new = 'assert s.count(needle) >= 1\ns = s.replace(needle, replacement, 1)'
assert text.count(old) == 1
path.write_text(text.replace(old, new, 1))
