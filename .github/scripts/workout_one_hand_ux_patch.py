from pathlib import Path

active_path = Path('lib/screens/active_workout.dart')
text = active_path.read_text()

# Helpers for the single actionable/current set and compact completed-set metadata.
if 'int _currentSetIndexFor(WorkoutExercise exercise)' not in text:
    marker = '  void _submitSetFromKeyboard(\n'
    helper = '''  int _currentSetIndexFor(WorkoutExercise exercise) {
    for (var index = 0; index < exercise.sets.length; index++) {
      if (!exercise.sets[index].isCompleted) return index;
    }
    return -1;
  }

  String? _setMetadataSummary(ExerciseSet set) {
    final parts = <String>[];
    if (set.type != SetType.normal) parts.add(set.type.label);
    if (set.rpe != null) parts.add('RPE ${_formatWeight(set.rpe!)}');
    if (set.rir != null) parts.add('RIR ${set.rir}');
    if (set.notes.trim().isNotEmpty) parts.add('Nota');
    return parts.isEmpty ? null : parts.join(' · ');
  }

'''
    if text.count(marker) != 1:
        raise SystemExit('submit keyboard marker not found exactly once')
    text = text.replace(marker, helper + marker, 1)

# Put set type inside the universal details dialog so secondary chips can be hidden.
text = text.replace(
    '    bool isWarmup = set.isWarmup;\n',
    '    var selectedSetType = set.type;\n',
    1,
)
old_warmup = '''              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Warm-up'),
                value: isWarmup,
                onChanged: (value) => setDialogState(() => isWarmup = value),
              ),
'''
new_type_picker = '''              DropdownButtonFormField<SetType>(
                key: ValueKey('set-details-type-${set.id}'),
                initialValue: selectedSetType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo set'),
                items: SetType.values
                    .map(
                      (type) => DropdownMenuItem<SetType>(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedSetType = value);
                },
              ),
              appDialogFieldGap,
'''
if old_warmup in text:
    text = text.replace(old_warmup, new_type_picker, 1)
elif "key: ValueKey('set-details-type-${set.id}')" not in text:
    raise SystemExit('warmup details control anchor not found')
text = text.replace(
    '      set.isWarmup = isWarmup;\n',
    '      set.type = selectedSetType;\n',
    1,
)

# Mark the first incomplete set as the current/actionable one.
loop_anchor = '''                        final exSet = exercise.sets[setIndex];
                        final setLabel =
'''
loop_replacement = '''                        final exSet = exercise.sets[setIndex];
                        final currentSetIndex = _currentSetIndexFor(exercise);
                        final isCurrentSet = setIndex == currentSetIndex;
                        final setMetadataSummary = _setMetadataSummary(exSet);
                        final setLabel =
'''
if loop_anchor in text:
    text = text.replace(loop_anchor, loop_replacement, 1)
elif 'final isCurrentSet = setIndex == currentSetIndex;' not in text:
    raise SystemExit('set loop anchor not found')

old_color = '''                              color: exSet.isCompleted
                                  ? colorScheme.tertiaryContainer.withValues(
                                      alpha: isDark ? 0.38 : 0.62,
                                    )
                                  : Colors.transparent,
'''
new_color = '''                              color: exSet.isCompleted
                                  ? colorScheme.tertiaryContainer.withValues(
                                      alpha: isDark ? 0.38 : 0.62,
                                    )
                                  : isCurrentSet
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: isDark ? 0.28 : 0.48,
                                    )
                                  : Colors.transparent,
'''
if old_color in text:
    text = text.replace(old_color, new_color, 1)
elif ': isCurrentSet' not in text:
    raise SystemExit('set color anchor not found')

old_border = '''                              border: Border.all(
                                color: exSet.isCompleted
                                    ? colorScheme.tertiary.withValues(
                                        alpha: 0.35,
                                      )
                                    : Colors.transparent,
                              ),
'''
new_border = '''                              border: Border.all(
                                color: exSet.isCompleted
                                    ? colorScheme.tertiary.withValues(
                                        alpha: 0.35,
                                      )
                                    : isCurrentSet
                                    ? colorScheme.primary
                                    : Colors.transparent,
                                width: isCurrentSet ? 1.6 : 1,
                              ),
'''
if old_border in text:
    text = text.replace(old_border, new_border, 1)
elif 'width: isCurrentSet ? 1.6 : 1,' not in text:
    raise SystemExit('set border anchor not found')

old_label = '''                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        displaySetLabel,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
'''
new_label = '''                                    SizedBox(
                                      width: 72,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            displaySetLabel,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (isCurrentSet)
                                            Container(
                                              key: ValueKey(
                                                'current-set-${exSet.id}',
                                              ),
                                              margin: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: colorScheme.primary,
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                'ORA',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onPrimary,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
'''
if old_label in text:
    text = text.replace(old_label, new_label, 1)
elif "'current-set-${exSet.id}'" not in text:
    raise SystemExit('set label anchor not found')

# Keep universal details access in the main row.
old_details_button = '''                                    IconButton(
                                      tooltip: 'RPE, RIR, note',
'''
new_details_button = '''                                    IconButton(
                                      key: ValueKey('set-details-${exSet.id}'),
                                      tooltip: 'RPE, RIR, tipo e note',
'''
if old_details_button in text:
    text = text.replace(old_details_button, new_details_button, 1)
elif "key: ValueKey('set-details-${exSet.id}')" not in text:
    raise SystemExit('set details button anchor not found')

# Add a large thumb-zone completion action only for the current set.
previous_marker = '                                if (previousSetLabel != null)\n'
if "key: ValueKey('thumb-complete-${exSet.id}')" not in text:
    thumb_button = '''                                if (isCurrentSet && !exSet.isCompleted)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      72,
                                      6,
                                      8,
                                      0,
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        key: ValueKey(
                                          'thumb-complete-${exSet.id}',
                                        ),
                                        onPressed: () => _toggleSetCompleted(
                                          exercise,
                                          exSet,
                                          setIndex,
                                        ),
                                        icon: const Icon(Icons.check_circle),
                                        label: const Text('Completa set'),
                                      ),
                                    ),
                                  ),
'''
    if text.count(previous_marker) != 1:
        raise SystemExit('previous set marker not found exactly once')
    text = text.replace(previous_marker, thumb_button + previous_marker, 1)

# Show the dense quick-control strip only on the current set. Completed sets get a one-line summary.
popup_marker = '                                      PopupMenuButton<SetType>(\n'
popup_index = text.find(popup_marker)
if popup_index < 0:
    raise SystemExit('set type quick-control popup not found')
block_start = text.rfind('                                Padding(\n', 0, popup_index)
if block_start < 0:
    raise SystemExit('secondary quick-control padding start not found')
block_end_marker = '                                ),\n                              ],\n                            ),\n'
block_end_anchor = text.find(block_end_marker, popup_index)
if block_end_anchor < 0:
    raise SystemExit('secondary quick-control padding end not found')
block_end = block_end_anchor + len('                                ),\n')
old_secondary = text[block_start:block_end]
if 'if (isCurrentSet)\n                                  Padding(' not in old_secondary:
    indented = '\n'.join('  ' + line for line in old_secondary.rstrip('\n').split('\n')) + '\n'
    replacement = '''                                if (isCurrentSet)
''' + indented + '''                                if (!isCurrentSet &&
                                    setMetadataSummary != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 72,
                                      top: 4,
                                      right: 8,
                                    ),
                                    child: Text(
                                      setMetadataSummary,
                                      key: ValueKey('set-meta-${exSet.id}'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
'''
    text = text[:block_start] + replacement + text[block_end:]

active_path.write_text(text)

# Regression tests for the one-hand hierarchy and details fallback.
test_path = Path('test/workout_ux_polish_v2_test.dart')
test_text = test_path.read_text()
if "one-hand UX promotes only the next pending set" not in test_text:
    insertion = r'''

  testWidgets('one-hand UX promotes only the next pending set', (tester) async {
    final first = ExerciseSet(weight: 50, reps: 8);
    final second = ExerciseSet(weight: 50, reps: 8);
    final exercise = _exercise('Bench', sets: [first, second]);
    final session = _session([exercise]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.editCompleted(
          session: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('current-set-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('current-set-${second.id}')), findsNothing);
    expect(find.byKey(ValueKey('thumb-complete-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thumb-complete-${second.id}')), findsNothing);
    expect(find.byKey(ValueKey('plates-${first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('plates-${second.id}')), findsNothing);

    final thumbComplete = find.byKey(ValueKey('thumb-complete-${first.id}'));
    await tester.ensureVisible(thumbComplete);
    await tester.tap(thumbComplete);
    await tester.pumpAndSettle();

    expect(first.isCompleted, isTrue);
    expect(find.byKey(ValueKey('current-set-${first.id}')), findsNothing);
    expect(find.byKey(ValueKey('current-set-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thumb-complete-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('plates-${first.id}')), findsNothing);
    expect(find.byKey(ValueKey('plates-${second.id}')), findsOneWidget);
  });

  testWidgets('set details keeps type editing available outside quick controls', (
    tester,
  ) async {
    final first = ExerciseSet(weight: 50, reps: 8, isCompleted: true);
    final second = ExerciseSet(weight: 50, reps: 8);
    final exercise = _exercise('Bench', sets: [first, second]);
    final session = _session([exercise]);

    await tester.pumpWidget(
      MaterialApp(
        home: ActiveWorkoutScreen.editCompleted(
          session: session,
          defaultRestSeconds: 90,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('plates-${first.id}')), findsNothing);
    final details = find.byKey(ValueKey('set-details-${first.id}'));
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();

    final typePicker = find.byKey(ValueKey('set-details-type-${first.id}'));
    expect(typePicker, findsOneWidget);
    await tester.tap(typePicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drop').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salva'));
    await tester.pumpAndSettle();

    expect(first.type, SetType.drop);
  });
'''
    closing = test_text.rfind('\n}')
    if closing < 0:
        raise SystemExit('test file closing brace not found')
    test_text = test_text[:closing] + insertion + test_text[closing:]
    test_path.write_text(test_text)
