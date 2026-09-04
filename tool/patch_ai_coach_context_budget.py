from pathlib import Path

path = Path('lib/ai_coach/local_ai_coach_service.dart')
text = path.read_text()

text = text.replace("import 'dart:convert';\n\n", '', 1)

old_import = "import 'ai_coach_context_router.dart';\n"
new_import = "import 'ai_coach_context_budget.dart';\nimport 'ai_coach_context_router.dart';\n"
if old_import not in text:
    raise RuntimeError('context router import anchor missing')
text = text.replace(old_import, new_import, 1)

start = text.index('  String _encodeBoundedContext(\n')
end = text.index('  String _conversationReference(\n', start)
replacement = '''  String _encodeBoundedContext(\n    Map<String, dynamic> original, {\n    required bool keepProgramHistory,\n  }) {\n    return AiCoachContextBudget.encode(\n      original,\n      charBudget: _chatContextCharBudget,\n      keepProgramHistory: keepProgramHistory,\n    );\n  }\n\n'''
text = text[:start] + replacement + text[end:]
path.write_text(text)
