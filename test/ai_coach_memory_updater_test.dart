import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_memory.dart';
import 'package:gymapp/ai_coach/ai_coach_memory_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores explicit training preferences without model inference', () async {
    const updater = AiCoachMemoryUpdater();

    final memory = await updater.updateFromUserText(
      'Preferisco i manubri per il petto. Voglio dare priorità ai deltoidi laterali.',
    );

    expect(memory.recurringPreferences, contains('i manubri per il petto'));
    expect(memory.recurringPreferences, contains('ai deltoidi laterali'));
    expect(memory.recurringLimitations, isEmpty);

    final persisted = await const AiCoachMemoryStore().load();
    expect(persisted.recurringPreferences, memory.recurringPreferences);
  });

  test('generic sentiment is not promoted to persistent training memory', () async {
    const updater = AiCoachMemoryUpdater();

    final memory = await updater.updateFromUserText(
      'Mi piace questa risposta, grazie.',
    );

    expect(memory.isEmpty, isTrue);
    expect(await const AiCoachMemoryStore().hasStoredValue(), isFalse);
  });

  test('stores explicit constraints and deduplicates repeated statements', () async {
    const updater = AiCoachMemoryUpdater();

    var memory = await updater.updateFromUserText('Evito il back squat.');
    memory = await updater.updateFromUserText(
      'Evito il back squat.',
      current: memory,
    );

    expect(memory.recurringLimitations, ['il back squat']);
  });

  test('ricorda che stores a user-controlled coaching note', () async {
    const updater = AiCoachMemoryUpdater();

    final memory = await updater.updateFromUserText(
      'Ricorda che di solito ho solo 60 minuti per allenarmi.',
    );

    expect(
      memory.coachingNotes,
      contains('di solito ho solo 60 minuti per allenarmi'),
    );
  });

  test('user can forget one item or clear all Coach memory', () async {
    const updater = AiCoachMemoryUpdater();
    var memory = await updater.updateFromUserText('Preferisco la panca piana.');
    memory = await updater.updateFromUserText(
      'Evito il back squat.',
      current: memory,
    );

    memory = await updater.updateFromUserText(
      'Dimentica back squat',
      current: memory,
    );
    expect(memory.recurringLimitations, isEmpty);
    expect(memory.recurringPreferences, isNotEmpty);

    memory = await updater.updateFromUserText(
      'Cancella tutta la memoria del Coach',
      current: memory,
    );
    expect(memory.recurringPreferences, isEmpty);
    expect(memory.recurringLimitations, isEmpty);
    expect(memory.coachingNotes, isEmpty);
  });

  test('mentioning clear-memory words does not clear without a command', () async {
    const updater = AiCoachMemoryUpdater();
    final original = await updater.updateFromUserText('Preferisco la panca piana.');

    final memory = await updater.updateFromUserText(
      'Non cancellare tutta la memoria del Coach.',
      current: original,
    );

    expect(memory.recurringPreferences, contains('la panca piana'));
  });

  test('persisted clear wins over stale screen memory on later turns', () async {
    const updater = AiCoachMemoryUpdater();
    final stale = await updater.updateFromUserText('Preferisco la panca piana.');

    final cleared = await updater.updateFromUserText(
      'Cancella tutta la memoria del Coach',
      current: stale,
    );
    expect(cleared.isEmpty, isTrue);

    final nextTurn = await updater.updateFromUserText(
      'Come mi alleno oggi?',
      current: stale,
    );
    expect(nextTurn.isEmpty, isTrue);
  });
}
