from pathlib import Path

path = Path('tool/patch_ai_model_fault_injection.py')
text = path.read_text()
old = "    text = replace_once(text, old, new, f'wrap {method}')\npath.write_text(text)\n"
new = "    engine_start = text.index('class FlutterGemmaLocalLlmEngine')\n    prefix = text[:engine_start]\n    engine = text[engine_start:]\n    engine = replace_once(engine, old, new, f'wrap {method}')\n    text = prefix + engine\npath.write_text(text)\n"
if text.count(old) != 1:
    raise RuntimeError(f'expected one loop replacement anchor, found {text.count(old)}')
path.write_text(text.replace(old, new, 1))
