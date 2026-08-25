from pathlib import Path

path = Path('tool/routine_system_v2.py')
text = path.read_text()
old = '''    "                                const PopupMenuItem(\\n                                  value: _ScheduleMenuAction.toggleArchive,",
    "                                const PopupMenuItem(\\n                                  value: _ScheduleMenuAction.folder,\\n                                  child: ListTile(\\n                                    leading: Icon(Icons.folder_outlined),\\n                                    title: Text('Cartella'),\\n                                  ),\\n                                ),\\n                                const PopupMenuItem(\\n                                  value: _ScheduleMenuAction.toggleArchive,",'''
new = '''    "                                PopupMenuItem(\\n                                  value: _ScheduleMenuAction.toggleArchive,",
    "                                const PopupMenuItem(\\n                                  value: _ScheduleMenuAction.folder,\\n                                  child: ListTile(\\n                                    leading: Icon(Icons.folder_outlined),\\n                                    title: Text('Cartella'),\\n                                  ),\\n                                ),\\n                                PopupMenuItem(\\n                                  value: _ScheduleMenuAction.toggleArchive,",'''
if old not in text:
    raise RuntimeError('routine v2 archive-menu patch anchor not found')
path.write_text(text.replace(old, new, 1))
