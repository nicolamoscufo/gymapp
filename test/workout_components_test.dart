import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ui/workout_components.dart';

void main() {
  testWidgets('compact exercise card exposes progress and expands on tap', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutCompactExerciseCard(
            exerciseId: 'bench',
            name: 'Panca piana',
            completedSets: 2,
            totalSets: 4,
            nextPrescription: '82.5 kg × 8',
            isComplete: false,
            accent: Colors.blue,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Panca piana'), findsOneWidget);
    expect(find.textContaining('2/4 set'), findsOneWidget);
    expect(find.textContaining('82.5 kg × 8'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expand-exercise-bench')));
    expect(tapped, isTrue);
  });

  testWidgets('completed compact exercise uses completed copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutCompactExerciseCard(
            exerciseId: 'row',
            name: 'Rematore',
            completedSets: 3,
            totalSets: 3,
            isComplete: true,
            accent: Colors.blue,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Completato · 3/3 set'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('rest panel keeps next set and one-hand controls visible', (
    tester,
  ) async {
    var minus = 0;
    var plus = 0;
    var skipped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: WorkoutRestPanel(
            exerciseName: 'Panca piana',
            countdown: '01:24',
            progress: 0.7,
            nextExerciseName: 'Panca piana',
            nextSetLabel: 'Serie 3',
            nextPrescription: '82.5 kg × 8',
            onMinusThirty: () => minus++,
            onPlusThirty: () => plus++,
            onSkip: () => skipped = true,
          ),
        ),
      ),
    );

    expect(find.text('01:24'), findsOneWidget);
    expect(find.text('PROSSIMO SET'), findsOneWidget);
    expect(find.text('82.5 kg × 8'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rest-minus-30')));
    await tester.tap(find.byKey(const ValueKey('rest-plus-30')));
    await tester.tap(find.byKey(const ValueKey('rest-skip')));

    expect(minus, 1);
    expect(plus, 1);
    expect(skipped, isTrue);
  });

  testWidgets('workout metric tile uses compact information hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkoutMetricTile(
            icon: Icons.check_circle_outline,
            label: 'Set',
            value: '8/12',
            helper: '67% completato',
          ),
        ),
      ),
    );

    expect(find.text('Set'), findsOneWidget);
    expect(find.text('8/12'), findsOneWidget);
    expect(find.text('67% completato'), findsOneWidget);
  });
}
