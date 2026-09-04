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

  /// Conversational Coach answers should be useful but compact. The system
  /// prompt already asks for 1-4 prioritized actions, so a 512-token hard
  /// output cap leaves enough room for a complete answer without letting a
  /// local generation consume the rest of the 4096-token context window.
  static const chat = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.chat,
    temperature: 0.30,
    randomSeed: 1,
    topK: 40,
    topP: 0.90,
    tokenBuffer: 1024,
    maxOutputTokens: 512,
  );

  /// JSON reports favor repeatability over stylistic variety. A lower
  /// temperature/top-k reduces malformed or unnecessarily verbose output.
  static const structuredReport = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.structuredReport,
    temperature: 0.15,
    randomSeed: 1,
    topK: 20,
    topP: 0.85,
    tokenBuffer: 1024,
    maxOutputTokens: 768,
  );

  /// Vision output is also strict JSON. Keep the same conservative decoding
  /// policy while reserving enough output for visible-change evidence.
  static const visionStructured = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.visionStructured,
    temperature: 0.15,
    randomSeed: 1,
    topK: 20,
    topP: 0.85,
    tokenBuffer: 1024,
    maxOutputTokens: 768,
  );

  /// Program Builder emits the largest structured payload in the app. Give it
  /// the highest reply budget, but still cap generation so a malformed draft
  /// cannot run until the entire model context is exhausted.
  static const programBuilder = AiCoachGenerationProfile(
    task: AiCoachGenerationTask.programBuilder,
    temperature: 0.20,
    randomSeed: 1,
    topK: 30,
    topP: 0.90,
    tokenBuffer: 1024,
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
