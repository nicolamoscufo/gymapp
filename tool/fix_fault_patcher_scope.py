from pathlib import Path

path = Path('tool/patch_ai_model_fault_injection.py')
text = path.read_text()

old_scope = "    text = replace_once(text, old, new, f'wrap {method}')\npath.write_text(text)\n"
new_scope = "    engine_start = text.index('class FlutterGemmaLocalLlmEngine')\n    prefix = text[:engine_start]\n    engine = text[engine_start:]\n    engine = replace_once(engine, old, new, f'wrap {method}')\n    text = prefix + engine\npath.write_text(text)\n"
if text.count(old_scope) != 1:
    raise RuntimeError(
        f'expected one loop replacement anchor, found {text.count(old_scope)}'
    )
text = text.replace(old_scope, new_scope, 1)

old_branch = """    if method == 'generateChatText':
        old = f\"\"\"  @override
  Future<String> {method}({{
{args}  }}) async {{
\"\"\"
        new = f\"\"\"  @override
  Future<String> {method}({{
{args}  }}) {{
    return _execution.runExclusive(() async {{
      await _execution.ensureReady(() => _ensureModel(supportImage: false));
      return _{method}Unlocked({call_args});
    }});
  }}

  Future<String> _{method}Unlocked({{
{args}  }}) async {{
\"\"\"
    else:
"""
new_branch = """    if method == 'generateText':
        old = \"\"\"  @override
  Future<String> generateText(String prompt) async {
\"\"\"
        new = \"\"\"  @override
  Future<String> generateText(String prompt) {
    return _execution.runExclusive(() async {
      await _execution.ensureReady(() => _ensureModel(supportImage: false));
      return _generateTextUnlocked(prompt);
    });
  }

  Future<String> _generateTextUnlocked(String prompt) async {
\"\"\"
    elif method == 'generateChatText':
        old = f\"\"\"  @override
  Future<String> {method}({{
{args}  }}) async {{
\"\"\"
        new = f\"\"\"  @override
  Future<String> {method}({{
{args}  }}) {{
    return _execution.runExclusive(() async {{
      await _execution.ensureReady(() => _ensureModel(supportImage: false));
      return _{method}Unlocked({call_args});
    }});
  }}

  Future<String> _{method}Unlocked({{
{args}  }}) async {{
\"\"\"
    else:
"""
if text.count(old_branch) != 1:
    raise RuntimeError(
        f'expected one method-branch anchor, found {text.count(old_branch)}'
    )
text = text.replace(old_branch, new_branch, 1)

path.write_text(text)
