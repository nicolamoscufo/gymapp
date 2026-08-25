import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/screens/home_ai_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app shell opens dashboard and new primary navigation', (
    tester,
  ) async {
    final now = DateTime.now();
    final schedule = Schedule(
      id: 'schedule_dashboard',
      title: 'Push A',
      week: 1,
      createdAt: now,
      exercises: [
        Exercise(
          id: 'exercise_dashboard',
          name: 'Panca',
          reps: 8,
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
      ],
      trainingWeekdays: [now.weekday],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeAiShell(
          themeMode: ThemeMode.system,
          onThemeModeChanged: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Prossimo allenamento'), findsOneWidget);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('AI Coach'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pumpAndSettle();
    expect(find.text('Schede'), findsWidgets);
    expect(find.text('Push A'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_month));
    await tester.pumpAndSettle();
    expect(find.text('Allenati'), findsWidgets);

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.text('Progressi'), findsWidgets);
    expect(find.text('Cronologia'), findsOneWidget);
    expect(find.text('Statistiche'), findsOneWidget);
    expect(find.text('Corpo'), findsOneWidget);
  });
}
