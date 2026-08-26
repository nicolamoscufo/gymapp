import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/progress_analytics.dart';
import 'package:gymapp/progress_intelligence.dart';
import 'package:gymapp/screens/exercise_detail.dart';
import 'package:gymapp/screens/progress_center.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('drill-down exposes exact smoothed comparison windows and PRs', () {
    final history = _history();
    final now = DateTime(2026, 8, 26, 12);
    final analytics = buildProgressAnalytics(history: history, now: now);

    final drilldown = buildExerciseProgressDrilldown(
      exerciseName: 'Panca',
      analytics: analytics,
      now: now,
    );

    expect(drilldown, isNotNull);
    expect(drilldown!.insight.momentum, ProgressMomentum.growing);
    expect(drilldown.estimatedOneRepMax.windowSize, 3);
    expect(drilldown.estimatedOneRepMax.previousAverage, isNotNull);
    expect(drilldown.estimatedOneRepMax.recentAverage, isNotNull);
    expect(
      drilldown.estimatedOneRepMax.recentAverage!,
      greaterThan(drilldown.estimatedOneRepMax.previousAverage!),
    );
    expect(drilldown.estimatedOneRepMax.changePercent, greaterThan(2));
    expect(drilldown.volume.windowSize, 3);
    expect(drilldown.volume.changePercent, greaterThan(2));
    expect(drilldown.personalRecords, isNotEmpty);
    expect(
      drilldown.personalRecords.every((record) => record.exerciseName == 'Panca'),
      isTrue,
    );
  });

  testWidgets('exercise detail explains momentum and exposes PR timeline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ExerciseDetailScreen(
          exerciseName: 'Panca',
          history: _history(),
          now: DateTime(2026, 8, 26, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('exercise-progress-drilldown')), findsOneWidget);
    expect(find.text('Analisi del trend'), findsOneWidget);
    expect(find.text('In crescita'), findsOneWidget);
    expect(find.text('e1RM blocchi'), findsOneWidget);
    expect(find.text('Volume blocchi'), findsOneWidget);

    final list = find.byType(ListView);
    for (var i = 0; i < 8 && find.text('PR timeline').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const ValueKey('exercise-pr-timeline')), findsOneWidget);
    expect(find.text('PR timeline'), findsOneWidget);
  });

  testWidgets('Progress Center opens drill-down from Focus and Exercises', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressCenterScreen(
            history: _history(),
            now: DateTime(2026, 8, 26, 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    final focusTile = find.byKey(const ValueKey('progress-focus-Panca'));
    for (var i = 0; i < 4 && focusTile.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -350));
      await tester.pumpAndSettle();
    }
    expect(focusTile, findsOneWidget);
    await tester.tap(focusTile);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(ExerciseDetailScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Esercizi'));
    await tester.pumpAndSettle();
    final exerciseTile = find.byKey(
      const ValueKey('progress-exercise-open-Panca'),
    );
    expect(exerciseTile, findsOneWidget);
    await tester.tap(exerciseTile);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
  });
}

List<WorkoutSession> _history() {
  final weights = [70.0, 72.5, 75.0, 80.0, 82.5, 85.0];
  return List.generate(weights.length, (index) {
    final start = DateTime(2026, 7, 15 + (index * 7), 18);
    return WorkoutSession(
      scheduleTitle: 'Push',
      startTime: start,
      endTime: start.add(const Duration(minutes: 65)),
      exercises: [
        WorkoutExercise(
          name: 'Panca',
          notes: '',
          muscleGroup: MuscleGroup.chest,
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(
              weight: weights[index],
              reps: 8,
              rir: 2,
              rpe: 8,
              isCompleted: true,
            ),
            ExerciseSet(
              weight: weights[index],
              reps: 8,
              rir: 2,
              rpe: 8,
              isCompleted: true,
            ),
          ],
        ),
      ],
    );
  });
}
