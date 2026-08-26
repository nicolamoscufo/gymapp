from pathlib import Path

path = Path('.github/scripts/add_schedule_history_core.py')
text = path.read_text()
start = text.index("upgrade = r'''")
text = text[:start] + text[start:].replace("upgrade = r'''", 'upgrade = r"""', 1)
end = text.index("\n'''\nreplace_once(", start)
text = text[:end] + '\n"""\nreplace_once(' + text[end + len("\n'''\nreplace_once("):]
path.write_text(text)
