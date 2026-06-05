import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/calendar_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('calendar shows completed workouts for selected day', (
    tester,
  ) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 9, 30);
    final session = WorkoutSession(
      scheduleTitle: 'Push',
      startTime: start,
      endTime: start.add(const Duration(minutes: 75)),
      exercises: [
        WorkoutExercise(
          name: 'Panca',
          notes: '',
          technique: IntensityTechnique.none,
          sets: [ExerciseSet(weight: 80, reps: 8, isCompleted: true)],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarScreen(
            schedules: const [],
            history: [session],
            defaultRestSeconds: 90,
            onRefresh: () {},
            onSaveSchedules: () {},
            showAppBar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Oggi: 0 schede - 1 svolti'), findsOneWidget);
    expect(find.text('Allenamenti svolti'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('09:30 - 1h 15m - 1 set - 640 kg'), findsOneWidget);
  });
}
