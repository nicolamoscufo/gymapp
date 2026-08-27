import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_action_protocol.dart';
import 'package:gymapp/ai_coach/chat_conversation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('program draft action payload survives conversation persistence', () async {
    final proposal = AiProgramActionProposal(
      kind: AiProgramActionKind.proposeProgram,
      summary: 'Upper Lower',
      rationale: 'Quattro giorni ben distribuiti.',
      confidence: 'medium',
      schedules: const [
        AiProgramScheduleDraft(
          draftKey: 'upper_a',
          title: 'Upper A',
          trainingWeekdays: [1],
          exercises: [
            AiProgramDraftExercise(
              name: 'Panca',
              sets: 3,
              reps: 8,
              weight: 80,
              muscleGroup: 'chest',
            ),
          ],
        ),
      ],
    );
    final conversation = ChatConversation(
      id: 'chat-1',
      title: 'Nuova scheda',
      messages: [
        ChatMessage(role: 'user', content: 'Fammi una scheda'),
        ChatMessage(
          role: 'assistant',
          content: proposal.summary,
          actionPayload: proposal.toJson(),
        ),
      ],
    );
    const store = ChatConversationStore();

    await store.saveConversation(conversation);
    final restored = (await store.loadAll()).single;
    final message = restored.messages.last;

    expect(message.hasActionPayload, isTrue);
    final restoredProposal = AiProgramActionProposal.fromActionPayload(
      message.actionPayload!,
    );
    expect(restoredProposal.schedules.single.title, 'Upper A');
    expect(restoredProposal.schedules.single.exercises.single.name, 'Panca');
  });

  test('legacy messages without action payload still deserialize', () {
    final message = ChatMessage.fromJson({
      'role': 'assistant',
      'content': 'Vecchio messaggio',
      'timestamp': '2026-08-26T12:00:00.000',
    });

    expect(message.content, 'Vecchio messaggio');
    expect(message.actionPayload, isNull);
    expect(message.hasActionPayload, isFalse);
  });
}
