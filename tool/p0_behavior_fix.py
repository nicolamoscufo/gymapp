from pathlib import Path

path = Path('lib/screens/ai_coach.dart')
text = path.read_text()
old = "      final selected = await showModalBottomSheet<List<ValidatedPlanAction>>(\n"
new = "      // Generation is complete: stop the app-bar spinner while the user reviews the diff.\n      setState(() => _isAnalyzingPlan = false);\n      final selected = await showModalBottomSheet<List<ValidatedPlanAction>>(\n"
if old not in text:
    raise RuntimeError('AI review sheet anchor not found')
text = text.replace(old, new, 1)
path.write_text(text)

path = Path('lib/app_data_store.dart')
text = path.read_text()
# Storage implementation changed, but the exported JSON contract did not.
# Keep version 5 so existing imports/tests remain backward-compatible.
text = text.replace("'version': 6,", "'version': 5,")
path.write_text(text)
