import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/screens/program_history.dart';

void main() {
  testWidgets('renders deterministic effectiveness for a program transition', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final schedule = Schedule(
      id: 'schedule-1',
      title: 'Upper A',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: const [],
      currentVersionId: 'version-2',
      currentVersionNumber: 2,
    );
    final version1 = ScheduleVersion(
      id: 'version-1',
      scheduleId: schedule.id,
      versionNumber: 1,
      createdAt: DateTime(2026, 8, 1),
      source: ScheduleVersionSource.user,
      snapshot: _snapshot(weight: 100),
    );
    final version2 = ScheduleVersion(
      id: 'version-2',
      scheduleId: schedule.id,
      versionNumber: 2,
      createdAt: DateTime(2026, 8, 15),
      source: ScheduleVersionSource.aiCoach,
      parentVersionId: version1.id,
      reason: 'Aumento carico panca',
      snapshot: _snapshot(weight: 105),
    );
    final history = [
      _session(
        id: 'before-1',
        versionId: version1.id,
        date: DateTime(2026, 8, 8),
        weight: 100,
      ),
      _session(
        id: 'before-2',
        versionId: version1.id,
        date: DateTime(2026, 8, 12),
        weight: 100,
      ),
      _session(
        id: 'after-1',
        versionId: version2.id,
        date: DateTime(2026, 8, 18),
        weight: 105,
      ),
      _session(
        id: 'after-2',
        versionId: version2.id,
        date: DateTime(2026, 8, 22),
        weight: 105,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ProgramHistoryScreen(
          schedule: schedule,
          history: history,
          loadVersions: () async => [version1, version2],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evoluzione programma'), findsOneWidget);
    expect(find.text('v1 → v2'), findsOneWidget);
    expect(find.text('Migliorato'), findsWidgets);
    expect(find.text('e1RM medio +5.0%'), findsOneWidget);
    expect(find.text('Sessioni esatte: 2 → 2'), findsOneWidget);
    expect(find.textContaining('Associazione, non causalità'), findsOneWidget);
    expect(find.text('Aumento carico panca'), findsOneWidget);
  });
}

Map<String, dynamic> _snapshot({required double weight}) => {
  'id': 'schedule-1',
  'title': 'Upper A',
  'week': 1,
  'createdAt': DateTime(2026, 8, 1).toIso8601String(),
  'exercises': [
    {
      'id': 'bench-1',
      'name': 'Panca piana',
      'set': 3,
      'reps': 5,
      'weight': weight,
    },
  ],
};

WorkoutSession _session({
  required String id,
  required String versionId,
  required DateTime date,
  required double weight,
}) {
  return WorkoutSession(
    id: id,
    scheduleId: 'schedule-1',
    scheduleVersionId: versionId,
    scheduleTitle: 'Upper A',
    startTime: date,
    endTime: date.add(const Duration(hours: 1)),
    exercises: [
      WorkoutExercise(
        sourceExerciseId: 'bench-1',
        name: 'Panca piana',
        notes: '',
        technique: IntensityTechnique.none,
        sets: [
          ExerciseSet(
            weight: weight,
            reps: 5,
            isCompleted: true,
          ),
        ],
      ),
    ],
  );
}
