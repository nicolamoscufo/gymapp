import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_generation_profile.dart';
import 'package:gymapp/ai_coach/ai_coach_model_config.dart';

void main() {
  group('AI Coach generation profiles', () {
    test('defines one bounded profile for each generation task', () {
      final contextWindow = const AiCoachModelConfig().maxTokens;
      final tasks = AiCoachGenerationProfiles.all
          .map((profile) => profile.task)
          .toSet();

      expect(tasks.length, AiCoachGenerationTask.values.length);
      expect(AiCoachGenerationProfiles.all.length, tasks.length);

      for (final profile in AiCoachGenerationProfiles.all) {
        expect(profile.temperature, inInclusiveRange(0.0, 1.0));
        expect(profile.topK, greaterThan(0));
        expect(profile.topP, inInclusiveRange(0.0, 1.0));
        expect(profile.tokenBuffer, greaterThan(0));
        expect(profile.maxOutputTokens, greaterThan(0));
        expect(profile.maxOutputTokens, lessThan(contextWindow));
        expect(profile.randomSeed, 1);
      }
    });

    test('chat stays concise while Program Builder gets the largest budget', () {
      expect(
        AiCoachGenerationProfiles.chat.maxOutputTokens,
        lessThan(AiCoachGenerationProfiles.structuredReport.maxOutputTokens),
      );
      expect(
        AiCoachGenerationProfiles.programBuilder.maxOutputTokens,
        greaterThan(AiCoachGenerationProfiles.structuredReport.maxOutputTokens),
      );
      expect(
        AiCoachGenerationProfiles.programBuilder.maxOutputTokens,
        greaterThanOrEqualTo(
          AiCoachGenerationProfiles.visionStructured.maxOutputTokens,
        ),
      );
    });

    test('structured generation is more deterministic than conversational chat', () {
      expect(
        AiCoachGenerationProfiles.structuredReport.temperature,
        lessThan(AiCoachGenerationProfiles.chat.temperature),
      );
      expect(
        AiCoachGenerationProfiles.visionStructured.temperature,
        lessThan(AiCoachGenerationProfiles.chat.temperature),
      );
      expect(
        AiCoachGenerationProfiles.structuredReport.topK,
        lessThan(AiCoachGenerationProfiles.chat.topK),
      );
    });

    test('Program Builder prompt selects the dedicated profile', () {
      final selected = AiCoachGenerationProfiles.forStructuredPrompt('''
You are the program builder.
TASK: program_draft
Return JSON only.
''');

      expect(selected.task, AiCoachGenerationTask.programBuilder);
      expect(selected.maxOutputTokens, 1024);
    });

    test('ordinary structured prompts keep the report profile', () {
      final selected = AiCoachGenerationProfiles.forStructuredPrompt('''
TASK: weekly_report
The user mentioned the phrase program_draft in a note.
''');

      expect(selected.task, AiCoachGenerationTask.structuredReport);
    });
  });
}
