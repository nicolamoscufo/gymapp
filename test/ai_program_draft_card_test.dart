import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/screens/ai_program_draft_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders multi-day proposal and exposes edit/save actions', (
    tester,
  ) async {
    var editCalls = 0;
    var saveCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiProgramDraftCard(
            proposal: _proposal(),
            onEdit: () => editCalls += 1,
            onSave: () => saveCalls += 1,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ai-program-draft-card')), findsOneWidget);
    expect(find.text('Nuova programmazione'), findsOneWidget);
    expect(find.text('Upper A'), findsOneWidget);
    expect(find.text('Lower A'), findsOneWidget);
    expect(find.text('3 × 6-10'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('edit-ai-program-draft')));
    await tester.tap(find.byKey(const ValueKey('save-ai-program-draft')));
    expect(editCalls, 1);
    expect(saveCalls, 1);
  });

  testWidgets('saving state disables both draft actions', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiProgramDraftCard(
            proposal: _proposal(),
            isSaving: true,
            onEdit: () => calls += 1,
            onSave: () => calls += 1,
          ),
        ),
      ),
    );

    final edit = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('edit-ai-program-draft')),
    );
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-ai-program-draft')),
    );
    expect(edit.onPressed, isNull);
    expect(save.onPressed, isNull);
    expect(find.text('Salvataggio…'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('saved draft cannot be edited or saved twice', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiProgramDraftCard(
            proposal: _proposal(),
            isSaved: true,
            onEdit: () => calls += 1,
            onSave: () => calls += 1,
          ),
        ),
      ),
    );

    final edit = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('edit-ai-program-draft')),
    );
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-ai-program-draft')),
    );
    expect(edit.onPressed, isNull);
    expect(save.onPressed, isNull);
    expect(find.text('Salvato'), findsOneWidget);
    expect(find.textContaining('già stata applicata'), findsOneWidget);
    expect(calls, 0);
  });
}

AiProgramActionProposal _proposal() => const AiProgramActionProposal(
  kind: AiProgramActionKind.proposeProgram,
  summary: 'Upper / Lower',
  rationale: 'Distribuzione su due sedute.',
  confidence: 'high',
  schedules: [
    AiProgramScheduleDraft(
      draftKey: 'upper_a',
      title: 'Upper A',
      goal: 'Ipertrofia',
      trainingWeekdays: [1],
      exercises: [
        AiProgramDraftExercise(
          name: 'Panca',
          sets: 3,
          reps: 8,
          weight: 80,
          targetMinReps: 6,
          targetMaxReps: 10,
          muscleGroup: 'chest',
        ),
      ],
    ),
    AiProgramScheduleDraft(
      draftKey: 'lower_a',
      title: 'Lower A',
      goal: 'Ipertrofia',
      trainingWeekdays: [2],
      exercises: [
        AiProgramDraftExercise(
          name: 'Squat',
          sets: 3,
          reps: 8,
          weight: 100,
          targetMinReps: 6,
          targetMaxReps: 10,
          muscleGroup: 'quadriceps',
        ),
      ],
    ),
  ],
);
