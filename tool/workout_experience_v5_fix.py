from pathlib import Path

active_path = Path('lib/screens/active_workout.dart')
active = active_path.read_text()
if 'Future<void> _loadReadinessBodyLogs()' not in active:
    marker = '  @override\n  void initState() {'
    method = '''  Future<void> _loadReadinessBodyLogs() async {
    final bundle = await AppDataStore.loadBundle();
    if (!mounted || _bodyLogs.isNotEmpty) return;
    setState(() {
      _bodyLogs = List<BodyLog>.from(bundle.bodyLogs);
    });
  }

'''
    if marker not in active:
        raise RuntimeError('initState marker not found for readiness body log loader')
    active = active.replace(marker, method + marker, 1)
active_path.write_text(active)

fatigue_path = Path('lib/workout_fatigue_analytics.dart')
fatigue = fatigue_path.read_text()
fatigue = fatigue.replace(
    '''      : referenceTime.difference(relevant.last.endTime).inHours.clamp(0, 100000);''',
    '''      : referenceTime
          .difference(relevant.last.endTime)
          .inHours
          .clamp(0, 100000)
          .toInt();''',
    1,
)
fatigue_path.write_text(fatigue)

prompt_path = Path('lib/ai_coach/ai_coach_prompts.dart')
prompt = prompt_path.read_text()
old = '- deterministic_analytics.progression_recommendations is the source of truth for increaseLoad, increaseReps, maintain, deload, or manual decisions when present. You may explain the decision and its uncertainty, but do not output a conflicting progression action.'
new = '- deterministic_analytics.progression_recommendations and deterministic_analytics.fatigue_readiness are the source of truth for progression and recovery decisions when present. Explain their evidence and uncertainty, but do not output a conflicting load, deload, volume, or fatigue decision.'
if old not in prompt:
    raise RuntimeError('AI deterministic progression rule not found')
prompt = prompt.replace(old, new, 1)
prompt_path.write_text(prompt)
