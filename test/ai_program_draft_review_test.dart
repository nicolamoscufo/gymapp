import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/screens/ai_program_draft_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('edits draft locally and returns the reviewed proposal', (
    tester,
  ) async {
    final key = GlobalKey<_DraftReviewHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _DraftReviewHarness(key: key, proposal: _proposal())),
    );

    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    expect(find.text('Rivedi proposta AI'), findsOneWidget);

    final title = find.byKey(const ValueKey('ai-draft-title-upper_a'));
    await tester.enterText(title, 'Upper Strength');

    final wednesday = find.byKey(const ValueKey('ai-draft-day-upper_a-3'));
    await tester.tap(wednesday);
    await tester.pump();

    final exerciseCard = find.byKey(
      const ValueKey('ai-draft-exercise-upper_a-1'),
    );
    await tester.scrollUntilVisible(exerciseCard, 180);
    final removeButtons = find.descendant(
      of: exerciseCard,
      matching: find.byTooltip('Rimuovi esercizio'),
    );
    await tester.tap(removeButtons);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ai-program-draft-done')));
    await tester.pumpAndSettle();

    final result = key.currentState!.result;
    expect(result, isNotNull);
    expect(result!.schedules.single.title, 'Upper Strength');
    expect(result.schedules.single.trainingWeekdays, [1, 3]);
    expect(result.schedules.single.exercises, hasLength(1));
    expect(result.schedules.single.exercises.single.name, 'Panca');
  });

  testWidgets('invalid local edit is blocked instead of returning a draft', (
    tester,
  ) async {
    final key = GlobalKey<_DraftReviewHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _DraftReviewHarness(key: key, proposal: _proposal())),
    );

    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    final firstExercise = find.byKey(
      const ValueKey('ai-draft-exercise-upper_a-0'),
    );
    final seriesField = find.descendant(
      of: firstExercise,
      matching: find.widgetWithText(TextFormField, 'Serie'),
    );
    await tester.enterText(seriesField, '0');
    await tester.tap(find.byKey(const ValueKey('ai-program-draft-done')));
    await tester.pump();

    expect(find.text('Correggi la bozza prima di continuare'), findsOneWidget);
    expect(find.text('Le serie devono essere tra 1 e 20.'), findsOneWidget);
    expect(key.currentState!.result, isNull);
  });
}

class _DraftReviewHarness extends StatefulWidget {
  final AiProgramActionProposal proposal;

  const _DraftReviewHarness({super.key, required this.proposal});

  @override
  State<_DraftReviewHarness> createState() => _DraftReviewHarnessState();
}

class _DraftReviewHarnessState extends State<_DraftReviewHarness> {
  AiProgramActionProposal? result;

  Future<void> _open() async {
    final reviewed = await Navigator.of(context).push<AiProgramActionProposal>(
      MaterialPageRoute(
        builder: (_) => AiProgramDraftReviewScreen(
          proposal: widget.proposal,
          currentSchedules: const [],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => result = reviewed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(onPressed: _open, child: const Text('Apri')),
      ),
    );
  }
}

AiProgramActionProposal _proposal() => const AiProgramActionProposal(
  kind: AiProgramActionKind.proposeProgram,
  summary: 'Upper A',
  rationale: 'Bozza di prova.',
  confidence: 'medium',
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
          muscleGroup: 'chest',
          restSeconds: 120,
        ),
        AiProgramDraftExercise(
          name: 'Rematore',
          sets: 3,
          reps: 10,
          weight: 60,
          muscleGroup: 'back',
          restSeconds: 120,
        ),
      ],
    ),
  ],
);
