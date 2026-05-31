import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/number_input.dart';
import 'package:gymapp/screens/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('schedule deletion can be undone', (tester) async {
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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsOneWidget);

    await tester.drag(find.text('Push'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsNothing);
    expect(find.text('Scheda eliminata.'), findsOneWidget);

    await tester.tap(find.text('ANNULLA'));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    expect(storedSchedules.single['id'], 'schedule_1');
  });

  testWidgets('unassigned exercise can be edited and saved', (tester) async {
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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
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
    await tester.tap(find.text('Panca'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Nome'),
      'Panca inclinata',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('Modifica'), findsNothing);
    expect(find.text('Panca inclinata'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    final storedExercises =
        storedSchedules.single['exercises'] as List<dynamic>;
    expect(storedExercises.single['name'], 'Panca inclinata');
    expect(storedExercises.single['muscleGroup'], 'unassigned');
  });

  testWidgets('editing exercise keeps old numbers when fields are empty', (
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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
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
    await tester.tap(find.text('Panca'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Nome'),
      'Panca inclinata',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Kg'), '');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('Modifica'), findsNothing);
    expect(find.text('Panca inclinata'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    final storedExercises =
        storedSchedules.single['exercises'] as List<dynamic>;
    expect(storedExercises.single['name'], 'Panca inclinata');
    expect(storedExercises.single['weight'], 80);
  });

  testWidgets('editing exercise can save after changing intensity technique', (
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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
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
    await tester.tap(find.text('Panca'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nessuna tecnica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top Set / Back off').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('Modifica'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    final storedExercises =
        storedSchedules.single['exercises'] as List<dynamic>;
    expect(storedExercises.single['technique'], 'topsetBackoff');
    expect(storedExercises.single['backoffReps'], 8);
  });

  testWidgets('form dialogs keep text fields readable on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          dialogTheme: const DialogThemeData(
            insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          ),
        ),
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.widgetWithText(TextField, 'Deload ogni')).width,
      greaterThan(220),
    );
  });

  testWidgets('exercise dialog keeps long field labels readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          dialogTheme: const DialogThemeData(
            insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          ),
        ),
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panca'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.widgetWithText(TextField, 'Step reps auto')).width,
      greaterThan(220),
    );
  });

  testWidgets('first launch shows onboarding setup', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Setup iniziale'), findsOneWidget);
    expect(find.text('Crea scheda'), findsOneWidget);
    expect(find.text('Scegli template'), findsNothing);
  });

  testWidgets('agenda shows planned workout and starts it', (tester) async {
    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      trainingWeekdays: [DateTime.now().weekday],
      exercises: [
        Exercise(
          id: 'exercise_1',
          name: 'Panca',
          reps: 8,
          set: 1,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Agenda prossimi 7 giorni'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Start').first);
    await tester.pumpAndSettle();

    expect(find.text('Panca'), findsOneWidget);
    expect(find.text('Fine'), findsOneWidget);
  });

  testWidgets('guided progression prefills next workout targets', (
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
          targetMinReps: 8,
          targetMaxReps: 10,
          technique: IntensityTechnique.none,
          progressionKgStep: 2.5,
        ),
      ],
    );
    final previousSession = WorkoutSession(
      id: 'session_1',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 5, 1, 10),
      endTime: DateTime(2026, 5, 1, 11),
      exercises: [
        WorkoutExercise(
          id: 'workout_exercise_1',
          name: 'Panca',
          notes: '',
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(id: 'set_1', weight: 80, reps: 10, isCompleted: true),
          ],
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': jsonEncode([previousSession.toJson()]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).at(1))
          .controller
          .text,
      '82.5',
    );
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).at(2))
          .controller
          .text,
      '8',
    );
  });

  test('auto backup bundle can be loaded for restore', () async {
    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: const [],
    );
    SharedPreferences.setMockInitialValues({
      AppDataKeys.autoBackupJson: jsonEncode({
        'version': 3,
        'schedules': [schedule.toJson()],
        'history': [],
        'bodyLogs': [],
      }),
    });

    final bundle = await AppDataStore.loadAutoBackupBundle();

    expect(bundle?.schedules.single.title, 'Push');
    expect(bundle?.recoveredFromCorruption, isTrue);
  });

  testWidgets('schedule exercises can be reordered from detail', (
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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
        Exercise(
          id: 'exercise_2',
          name: 'Squat',
          reps: 5,
          set: 4,
          notes: '',
          weight: 100,
          technique: IntensityTechnique.none,
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

    await tester.drag(
      find.byKey(const ValueKey('exercise-reorder-exercise_1')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Squat')).dy,
      lessThan(tester.getTopLeft(find.text('Panca')).dy),
    );

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    final storedExercises =
        storedSchedules.single['exercises'] as List<dynamic>;
    expect(storedExercises.map((entry) => entry['id']), [
      'exercise_2',
      'exercise_1',
    ]);
  });

  testWidgets('exercise reorder can move across multiple cards', (
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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
        Exercise(
          id: 'exercise_2',
          name: 'Squat',
          reps: 5,
          set: 4,
          notes: '',
          weight: 100,
          technique: IntensityTechnique.none,
        ),
        Exercise(
          id: 'exercise_3',
          name: 'Stacco',
          reps: 5,
          set: 3,
          notes: '',
          weight: 120,
          technique: IntensityTechnique.none,
        ),
        Exercise(
          id: 'exercise_4',
          name: 'Military press',
          reps: 6,
          set: 3,
          notes: '',
          weight: 50,
          technique: IntensityTechnique.none,
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

    await tester.drag(
      find.byKey(const ValueKey('exercise-reorder-exercise_1')),
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final storedSchedules =
        jsonDecode(prefs.getString('schedules')!) as List<dynamic>;
    final storedExercises =
        storedSchedules.single['exercises'] as List<dynamic>;
    expect(storedExercises.map((entry) => entry['id']), [
      'exercise_2',
      'exercise_3',
      'exercise_4',
      'exercise_1',
    ]);
  });

  testWidgets('active workout does not show quick set buttons', (tester) async {
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
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
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

    expect(find.text('-2.5kg'), findsNothing);
    expect(find.text('+2.5kg'), findsNothing);
    expect(find.text('-1 rep'), findsNothing);
    expect(find.text('+1 rep'), findsNothing);
  });

  testWidgets('active workout rest timer is manual per exercise', (
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

  testWidgets('active workout set inputs keep focus while autosaving', (
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

    final weightField = find.byType(TextFormField).at(1);
    await tester.tap(weightField);
    await tester.pump();

    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).at(1))
          .focusNode
          .hasFocus,
      isTrue,
    );

    tester.testTextInput.enterText('85');
    await tester.pump(const Duration(milliseconds: 1200));

    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).at(1))
          .focusNode
          .hasFocus,
      isTrue,
    );

    tester.testTextInput.enterText('87.5');
    await tester.pump();

    final repsField = find.byType(TextFormField).at(2);
    await tester.tap(repsField);
    await tester.pump();
    tester.testTextInput.enterText('12');
    await tester.pump(const Duration(milliseconds: 1200));

    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).at(2))
          .focusNode
          .hasFocus,
      isTrue,
    );

    final prefs = await SharedPreferences.getInstance();
    final storedSession =
        jsonDecode(prefs.getString(AppDataKeys.currentSession)!)
            as Map<String, dynamic>;
    final storedSet =
        (((storedSession['exercises'] as List<dynamic>).single
                        as Map<String, dynamic>)['sets']
                    as List<dynamic>)
                .single
            as Map<String, dynamic>;
    expect(storedSet['weight'], 87.5);
    expect(storedSet['reps'], 12);
  });

  testWidgets('completed improved set shows trophy volume delta', (
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
        ),
      ],
    );
    final previousSession = WorkoutSession(
      id: 'session_1',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 5, 1, 10),
      endTime: DateTime(2026, 5, 1, 11),
      exercises: [
        WorkoutExercise(
          id: 'workout_exercise_1',
          name: 'Panca',
          notes: '',
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(id: 'set_1', weight: 70, reps: 8, isCompleted: true),
          ],
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': jsonEncode([previousSession.toJson()]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '80');
    await tester.tap(find.byIcon(Icons.check).last);
    await tester.pump();

    expect(find.byIcon(Icons.emoji_events), findsWidgets);
    expect(find.text('Volume +80 kg'), findsOneWidget);
  });

  testWidgets('history shows exercise progress summaries', (tester) async {
    final oldSession = WorkoutSession(
      id: 'session_1',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 5, 1, 10),
      endTime: DateTime(2026, 5, 1, 11),
      exercises: [
        WorkoutExercise(
          id: 'workout_exercise_1',
          name: 'Panca',
          notes: '',
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(id: 'set_1', weight: 70, reps: 8, isCompleted: true),
          ],
        ),
      ],
    );
    final newSession = WorkoutSession(
      id: 'session_2',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 5, 8, 10),
      endTime: DateTime(2026, 5, 8, 11),
      exercises: [
        WorkoutExercise(
          id: 'workout_exercise_2',
          name: 'Panca',
          notes: '',
          technique: IntensityTechnique.none,
          sets: [
            ExerciseSet(id: 'set_2', weight: 80, reps: 8, isCompleted: true),
          ],
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': '[]',
      'history': jsonEncode([oldSession.toJson(), newSession.toJson()]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cronologia'));
    await tester.pumpAndSettle();

    expect(find.text('Progressi esercizi'), findsOneWidget);
    expect(find.text('1 miglioramenti recenti'), findsOneWidget);

    await tester.tap(find.text('Push').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Top set:'), findsNothing);

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.emoji_events),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Progressi esercizi'));
    await tester.pumpAndSettle();

    expect(find.text('Panca'), findsWidgets);
    expect(find.textContaining('+80 kg'), findsOneWidget);
  });

  testWidgets('history deletion can be undone', (tester) async {
    final session = WorkoutSession(
      id: 'session_1',
      scheduleTitle: 'Pull',
      startTime: DateTime(2026, 4, 1, 10),
      endTime: DateTime(2026, 4, 1, 11),
      exercises: [
        WorkoutExercise(
          id: 'workout_exercise_1',
          name: 'Rematore',

          sets: [
            ExerciseSet(id: 'set_1', weight: 60, reps: 10, isCompleted: true),
          ],
          notes: '',
          technique: IntensityTechnique.none,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': '[]',
      'history': jsonEncode([session.toJson()]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cronologia'));
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsNothing);
    expect(find.text('Allenamento eliminato.'), findsOneWidget);

    await tester.tap(find.text('ANNULLA'));
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final storedHistory =
        jsonDecode(prefs.getString('history')!) as List<dynamic>;
    expect(storedHistory.single['id'], 'session_1');
  });

  test('legacy json gets generated ids and keeps them after serialization', () {
    final schedule = Schedule.fromJson(<String, dynamic>{
      'title': 'Legacy',
      'week': 1,
      'createdAt': DateTime(2026).toIso8601String(),
      'exercises': [
        <String, dynamic>{
          'name': 'Squat',
          'reps': 5,
          'set': 5,
          'notes': '',
          'weight': 100,
        },
      ],
    });

    final restored = Schedule.fromJson(schedule.toJson());

    expect(schedule.id, isNotEmpty);
    expect(schedule.exercises.single.id, isNotEmpty);
    expect(schedule.exercises.single.muscleGroup, MuscleGroup.unassigned);
    expect(restored.id, schedule.id);
    expect(restored.exercises.single.id, schedule.exercises.single.id);
  });

  test('muscle group survives exercise serialization', () {
    final exercise = Exercise.fromJson(<String, dynamic>{
      'name': 'Panca piana',
      'reps': 8,
      'set': 4,
      'notes': '',
      'weight': 90,
      'muscleGroup': 'Petto',
      'technique': 'none',
    });

    final restored = Exercise.fromJson(exercise.toJson());

    expect(exercise.muscleGroup, MuscleGroup.chest);
    expect(restored.muscleGroup, MuscleGroup.chest);
    expect(restored.toJson()['muscleGroup'], 'chest');
  });

  test('schedule week advances automatically each Monday', () {
    final schedule = Schedule(
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 5, 18),
      exercises: [],
    );

    expect(schedule.currentWeek(now: DateTime(2026, 5, 18)), 1);
    expect(schedule.currentWeek(now: DateTime(2026, 5, 24)), 1);
    expect(schedule.currentWeek(now: DateTime(2026, 5, 25)), 2);
  });

  test('workout exercise keeps muscle group and previous weights', () {
    final exercise = WorkoutExercise(
      name: 'Rematore',
      notes: '',
      muscleGroup: MuscleGroup.back,
      technique: IntensityTechnique.none,
      sets: [ExerciseSet(weight: 70, reps: 10, isCompleted: true)],
      previousWeights: [65, 67.5],
    );

    final restored = WorkoutExercise.fromJson(exercise.toJson());

    expect(restored.muscleGroup, MuscleGroup.back);
    expect(restored.previousWeights, [65, 67.5]);
  });

  test('set metadata survives serialization', () {
    final set = ExerciseSet(
      weight: 100,
      reps: 5,
      isCompleted: true,
      isWarmup: true,
      rpe: 7.5,
      rir: 2,
      notes: 'Tecnica pulita',
    );

    final restored = ExerciseSet.fromJson(set.toJson());

    expect(restored.isWarmup, isTrue);
    expect(restored.rpe, 7.5);
    expect(restored.rir, 2);
    expect(restored.notes, 'Tecnica pulita');
  });

  test('number parser accepts comma decimals', () {
    expect(parseDecimalInput('72,5'), 72.5);
    expect(parseDecimalInput('72.5'), 72.5);
    expect(parseDecimalInput(''), isNull);
  });

  testWidgets('home handles large text in landscape', (tester) async {
    tester.view.physicalSize = const Size(900, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push accessibile',
      week: 1,
      createdAt: DateTime(2026),
      trainingWeekdays: [DateTime.now().weekday],
      exercises: [
        Exercise(
          id: 'exercise_1',
          name: 'Panca',
          reps: 8,
          set: 3,
          notes: '',
          weight: 80,
          technique: IntensityTechnique.none,
        ),
      ],
    );

    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(900, 390),
          textScaler: TextScaler.linear(1.7),
          highContrast: true,
        ),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Push accessibile'), findsWidgets);
    expect(find.textContaining('Agenda'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
