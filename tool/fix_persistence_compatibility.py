from pathlib import Path

# Keep supported legacy omissions distinct from actual corruption.
p = Path('lib/persistence_recovery.dart')
s = p.read_text()

s = s.replace(
    'Object? decode(String key, Object fallback)',
    'Object? decode(String key, Object? fallback)',
)

old = """  static PersistenceRecoverySnapshot decodeLegacyStorage(
    Map<String, Object?> values,
  ) {
    final context = _RecoveryContext();
"""
new = """  static PersistenceRecoverySnapshot decodeLegacyStorage(
    Map<String, Object?> values,
  ) {
    final context = _RecoveryContext(missingIdsAreCorruption: false);
"""
assert s.count(old) == 1
s = s.replace(old, new, 1)

old = """      if (rawExercises == null && allowPartial) {
        context.recovered = true;
      } else if (rawExercises is List) {
"""
new = """      if (rawExercises == null) {
        // Missing exercise arrays are supported by older persisted sessions.
      } else if (rawExercises is List) {
"""
assert s.count(old) == 1
s = s.replace(old, new, 1)

old = """      if (rawSets == null) {
        context.recovered = true;
      } else if (rawSets is List) {
"""
new = """      if (rawSets == null) {
        // Missing set arrays are supported by older persisted exercises.
      } else if (rawSets is List) {
"""
assert s.count(old) == 1
s = s.replace(old, new, 1)

old = """  static String _stableId(
    Object? raw,
    String fallback,
    _RecoveryContext context,
  ) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    context.recovered = true;
    return fallback;
  }
"""
new = """  static String _stableId(
    Object? raw,
    String fallback,
    _RecoveryContext context,
  ) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (context.missingIdsAreCorruption) context.recovered = true;
    return fallback;
  }
"""
assert s.count(old) == 1
s = s.replace(old, new, 1)

old = """class _RecoveryContext {
  bool recovered = false;
  bool rootCorruption = false;
"""
new = """class _RecoveryContext {
  final bool missingIdsAreCorruption;

  _RecoveryContext({this.missingIdsAreCorruption = true});

  bool recovered = false;
  bool rootCorruption = false;
"""
assert s.count(old) == 1
s = s.replace(old, new, 1)
p.write_text(s)

# Regression: supported no-id legacy payloads must migrate without a corruption
# banner, while still receiving deterministic stable IDs.
p = Path('test/persistence_fault_injection_test.dart')
s = p.read_text()
marker = """  test('malformed legacy root falls back to the last coherent auto backup', () async {
"""
test = """  test('missing legacy ids migrate deterministically without corruption state', () async {
    SharedPreferences.setMockInitialValues({
      AppDataKeys.schedules: jsonEncode([
        {
          'title': 'Legacy Push',
          'week': 1,
          'createdAt': '2026-09-01T00:00:00.000',
          'exercises': [
            {
              'name': 'Panca',
              'reps': 8,
              'set': 3,
              'weight': 80,
            },
          ],
        },
      ]),
    });

    final bundle = await AppDataStore.loadBundle();

    expect(bundle.recoveredFromCorruption, isFalse);
    expect(bundle.schedules.single.id, 'legacy_schedule_0');
    expect(
      bundle.schedules.single.exercises.single.id,
      'legacy_schedule_0_exercise_0',
    );
  });

""" + marker
assert s.count(marker) == 1
s = s.replace(marker, test, 1)
p.write_text(s)
