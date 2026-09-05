enum AiCoachGenerationTask {
  chat,
  structuredReport,
  visionStructured,
  programBuilder,
}

class AiCoachGenerationProfile {
  final AiCoachGenerationTask task;
  final double temperature;
  final int randomSeed;
  final int topK;
  final double topP;
  final int tokenBuffer;
  final int maxOutputTokens;

  const AiCoachGenerationProfile({
    required this.task,
    required this.temperature,
    required this.randomSeed,
    required this.topK,
    required this.topP,
    required this.tokenBuffer,
    required this.maxOutputTokens,
  });
}

class AiCoachGenerationProfiles {
  const AiCoachGenerationProfiles._();

  /// Conversational Coach answers should be useful but compact. The service
  /// already sends a single active user turn plus bounded reference context,
  /// so a large chat tokenBuffer only reduces the effective room available to
  /// the grounded app context. Keep the runtime buffer close to flutter_gemma's
  /// default and reserve reply length separately with maxOutputTokens.
  static const chat = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.chat,
    temperature: 0.30,
    randomSeed: 1,
    topK: 40,
    topP: 0.90,
    tokenBuffer: 256,
    maxOutputTokens: 512,
  );

  /// JSON reports favor repeatability over stylistic variety. Structured tasks
  /// are one-shot requests, so they also do not need a 1024-token chat buffer.
  static const structuredReport = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.structuredReport,
    temperature: 0.15,
    randomSeed: 1,
    topK: 20,
    topP: 0.85,
    tokenBuffer: 256,
    maxOutputTokens: 768,
  );

  /// Vision output is strict JSON. Keep the same conservative decoding policy
  /// and a small context-management buffer so image prompts retain their
  /// textual grounding.
  static const visionStructured = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.visionStructured,
    temperature: 0.15,
    randomSeed: 1,
    topK: 20,
    topP: 0.85,
    tokenBuffer: 256,
    maxOutputTokens: 768,
  );

  /// Program Builder emits the largest structured payload in the app. Give it
  /// the highest reply budget and a slightly larger context-management buffer,
  /// while still leaving substantially more room for the actual user/program
  /// evidence than the previous 1024-token setting.
  static const programBuilder = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.programBuilder,
    temperature: 0.20,
    randomSeed: 1,
    topK: 30,
    topP: 0.90,
    tokenBuffer: 384,
    maxOutputTokens: 1024,
  );

  static const all = <AiCoachGenerationProfile>[
    chat,
    structuredReport,
    visionStructured,
    programBuilder,
  ];

  static AiCoachGenerationProfile forStructuredPrompt(String prompt) {
    if (RegExp(
      r'TASK:\s*program_draft\b',
      caseSensitive: false,
    ).hasMatch(prompt)) {
      return programBuilder;
    }
    return structuredReport;
  }
}
