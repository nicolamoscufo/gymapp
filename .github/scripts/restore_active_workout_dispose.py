from pathlib import Path

path = Path('lib/screens/active_workout.dart')
text = path.read_text()
marker = '  Future<void> _finishWorkout() async {'
if marker not in text:
    raise SystemExit('finish workout marker not found')
if 'void dispose() {' in text:
    raise SystemExit('dispose already present; refusing duplicate insertion')

dispose = '''  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prBannerTimer?.cancel();
    _prBannerTimer = null;
    _handoffPulseTimer?.cancel();
    _handoffPulseTimer = null;
    _handoffClearTimer?.cancel();
    _handoffClearTimer = null;
    _restController.dispose();
    _durationTimer?.cancel();
    _workoutScrollController.dispose();
    if (!widget.editCompletedSession) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

'''
path.write_text(text.replace(marker, dispose + marker, 1))
