from pathlib import Path

path = Path('test/home_undo_test.dart')
text = path.read_text()

old = """  testWidgets('active workout rest timer is manual per exercise', (
    tester,
  ) async {
    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          id: 'exercise_1',
          name: 'Panca',
          reps: 8,
          set: 1,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
          restSeconds: 90,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'sec'), '45');
    await tester.tap(find.byIcon(Icons.check).last);
    await tester.pump();

    expect(find.textContaining('Rest '), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(find.text('Rest 00:45'), findsOneWidget);
  });
"""

new = """  testWidgets('active workout starts rest timer after completing set', (
    tester,
  ) async {
    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: [
        Exercise(
          id: 'exercise_1',
          name: 'Panca',
          reps: 8,
          set: 1,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
          restSeconds: 90,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'sec'), '45');
    await tester.tap(find.byIcon(Icons.check).last);
    await tester.pump();

    expect(find.textContaining('Rest 00:'), findsOneWidget);
    expect(find.textContaining('Recupero 00:'), findsOneWidget);
    expect(find.text('Salta'), findsOneWidget);
  });
"""

count = text.count(old)
if count != 1:
    raise RuntimeError(f'expected 1 legacy rest timer test, found {count}')

path.write_text(text.replace(old, new, 1))
