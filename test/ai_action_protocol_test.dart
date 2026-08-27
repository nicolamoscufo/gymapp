import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('validates and atomically creates a multi-day program', () {
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.proposeProgram,
      summary: 'Upper Lower 4 giorni',
      rationale: 'Quattro sedute coerenti con la richiesta.',
      confidence: 'high',
      schedules: [
        _newDraft('upper_a', 'Upper A', 1),
        _newDraft('lower_a', 'Lower A', 2, exercise: 'Squat'),
        _newDraft('upper_b', 'Upper B', 4),
        _newDraft('lower_b', 'Lower B', 5, exercise: 'Stacco rumeno'),
      ],
    );
    final schedules = <Schedule>[];
    const service = AiActionProtocolService();

    final validation = service.validate(proposal, schedules);
    expect(validation.isValid, isTrue, reason: validation.errors.join(', '));

    final result = service.apply(
      schedules,
      proposal,
      now: DateTime(2026, 8, 26),
    );
    expect(result.applied, isTrue);
    expect(result.createdSchedules, 4);
    expect(result.modifiedSchedules, 0);
    expect(schedules, hasLength(4));
    expect(schedules.map((e) => e.title), containsAll(['Upper A', 'Lower A', 'Upper B', 'Lower B']));
    expect(schedules.expand((e) => e.exercises).every((e) => e.id.isNotEmpty), isTrue);
    expect(schedules.every((e) => e.currentVersionId == null), isTrue);
  });

  test('proposed program rejects invented persistent identifiers', () {
    final bad = _newDraft('day_1', 'Day 1', 1).copyWith(
      baseScheduleId: 'invented-schedule',
      baseVersionId: 'invented-version',
      exercises: [
        _exerciseDraft('Panca').copyWith(sourceExerciseId: 'invented-exercise'),
      ],
    );
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.proposeProgram,
      summary: 'Nuovo programma',
      rationale: 'Test',
      schedules: [bad],
    );

    final result = const AiActionProtocolService().validate(proposal, const []);
    expect(result.isValid, isFalse);
    expect(result.errors, contains('day_1:proposed_program_cannot_reference_base_schedule'));
    expect(result.errors, contains('day_1:exercise_0:proposed_program_cannot_reference_exercise'));
  });

  test('modify program preserves exact existing ids and generates ids for additions', () {
    final base = _baseSchedule();
    final draft = AiProgramScheduleDraft(
      draftKey: 'push_modified',
      baseScheduleId: base.id,
      baseVersionId: base.currentVersionId!,
      title: 'Push evoluta',
      goal: 'Ipertrofia',
      mesocycleWeeks: 8,
      deloadEveryWeeks: 4,
      trainingWeekdays: const [1, 4],
      programBlock: 'Accumulo',
      cycleNotes: 'AI draft',
      exercises: [
        _exerciseDraft('Panca', sourceId: 'bench', weight: 82.5),
        _exerciseDraft('Croci ai cavi', weight: 20),
      ],
    );
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.modifyProgram,
      summary: 'Aggiorno Push',
      rationale: 'Progressione e nuovo accessorio.',
      confidence: 'medium',
      schedules: [draft],
    );
    final schedules = [base];

    final result = const AiActionProtocolService().apply(schedules, proposal);
    expect(result.applied, isTrue);
    expect(result.createdSchedules, 0);
    expect(result.modifiedSchedules, 1);
    expect(schedules.single.id, 'push');
    expect(schedules.single.currentVersionId, 'push-v3');
    expect(schedules.single.currentVersionNumber, 3);
    expect(schedules.single.exercises.first.id, 'bench');
    expect(schedules.single.exercises.first.weight, 82.5);
    expect(schedules.single.exercises.last.id, isNotEmpty);
    expect(schedules.single.exercises.last.id, isNot('bench'));
  });

  test('stale base version rejects the whole program without partial mutation', () {
    final base = _baseSchedule();
    final originalTitle = base.title;
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.modifyProgram,
      summary: 'Modifica',
      rationale: 'Test stale.',
      schedules: [
        AiProgramScheduleDraft(
          draftKey: 'push',
          baseScheduleId: base.id,
          baseVersionId: 'push-v2',
          title: 'Titolo che non deve essere applicato',
          exercises: [
            _exerciseDraft('Panca', sourceId: 'bench', weight: 90),
          ],
        ),
        _newDraft('new_day', 'Nuovo giorno', 5),
      ],
    );
    final schedules = [base];

    final result = const AiActionProtocolService().apply(schedules, proposal);
    expect(result.applied, isFalse);
    expect(result.errors.any((e) => e.endsWith(':stale_base_version')), isTrue);
    expect(schedules, hasLength(1));
    expect(schedules.single.title, originalTitle);
    expect(schedules.single.exercises.single.weight, 80);
  });

  test('one invalid schedule prevents every draft from being applied', () {
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.proposeProgram,
      summary: 'Due giorni',
      rationale: 'Atomic test.',
      schedules: [
        _newDraft('valid', 'Valid', 1),
        _newDraft('invalid', 'Invalid', 2).copyWith(
          exercises: [_exerciseDraft('Broken').copyWith(sets: 0)],
        ),
      ],
    );
    final schedules = <Schedule>[];

    final result = const AiActionProtocolService().apply(schedules, proposal);
    expect(result.applied, isFalse);
    expect(schedules, isEmpty);
    expect(result.errors, contains('invalid:exercise_0:invalid_sets'));
  });

  test('modify rejects unknown and duplicate source exercise ids', () {
    final base = _baseSchedule();
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.modifyProgram,
      summary: 'Bad refs',
      rationale: 'Test refs.',
      schedules: [
        AiProgramScheduleDraft(
          draftKey: 'push',
          baseScheduleId: base.id,
          baseVersionId: base.currentVersionId!,
          title: base.title,
          exercises: [
            _exerciseDraft('Panca 1', sourceId: 'bench'),
            _exerciseDraft('Panca 2', sourceId: 'bench'),
            _exerciseDraft('Unknown', sourceId: 'not-real'),
          ],
        ),
      ],
    );

    final result = const AiActionProtocolService().validate(proposal, [base]);
    expect(result.isValid, isFalse);
    expect(result.errors, contains('push:exercise_1:duplicate_source_exercise'));
    expect(result.errors, contains('push:exercise_2:unknown_source_exercise'));
  });

  test('program action intent gate only catches mutation requests', () {
    expect(looksLikeProgramActionIntent('Fammi una scheda upper lower 4 giorni'), isTrue);
    expect(looksLikeProgramActionIntent('Cambia la mia routine attuale'), isTrue);
    expect(looksLikeProgramActionIntent('Create a new workout plan'), isTrue);
    expect(looksLikeProgramActionIntent('Come sta andando la mia scheda?'), isFalse);
    expect(looksLikeProgramActionIntent('Analizza la mia panca'), isFalse);
  });

  test('payload roundtrip preserves the editable program draft', () {
    final original = AiProgramActionProposal(
      kind: AiProgramActionKind.proposeProgram,
      summary: 'Programma',
      rationale: 'Rationale',
      evidence: const ['storico', 'profilo'],
      confidence: 'high',
      schedules: [_newDraft('day_1', 'Upper', 1)],
    );

    final restored = AiProgramActionProposal.fromActionPayload(original.toJson());
    expect(restored.kind, AiProgramActionKind.proposeProgram);
    expect(restored.summary, original.summary);
    expect(restored.schedules.single.draftKey, 'day_1');
    expect(restored.schedules.single.exercises.single.name, 'Panca');
  });
}

AiProgramScheduleDraft _newDraft(
  String key,
  String title,
  int weekday, {
  String exercise = 'Panca',
}) => AiProgramScheduleDraft(
  draftKey: key,
  title: title,
  goal: 'Ipertrofia',
  mesocycleWeeks: 8,
  deloadEveryWeeks: 4,
  trainingWeekdays: [weekday],
  programBlock: 'Accumulo',
  exercises: [_exerciseDraft(exercise)],
);

AiProgramDraftExercise _exerciseDraft(
  String name, {
  String sourceId = '',
  double weight = 80,
}) => AiProgramDraftExercise(
  sourceExerciseId: sourceId,
  name: name,
  sets: 3,
  reps: 8,
  weight: weight,
  muscleGroup: name.toLowerCase().contains('squat') ? 'quadriceps' : 'chest',
  equipment: 'bilanciere',
  movementPattern: 'spinta',
  targetMinReps: 6,
  targetMaxReps: 10,
  technique: 'none',
  restSeconds: 120,
  progressionKgStep: 2.5,
  progressionRepStep: 1,
  progressionScheme: 'doubleProgression',
);

Schedule _baseSchedule() => Schedule(
  id: 'push',
  title: 'Push',
  week: 2,
  createdAt: DateTime(2026, 7, 1),
  goal: 'Ipertrofia',
  mesocycleWeeks: 8,
  deloadEveryWeeks: 4,
  trainingWeekdays: const [1, 4],
  programBlock: 'Accumulo',
  cycleNumber: 2,
  currentVersionId: 'push-v3',
  currentVersionNumber: 3,
  exercises: [
    Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      muscleGroup: MuscleGroup.chest,
      technique: IntensityTechnique.none,
    ),
  ],
);
