class AiCoachModelConfig {
  /// Total LiteRT-LM context window (system prompt + input + generated reply).
  /// 2048 was too small once deterministic workout context and a chat turn
  /// were combined, causing otherwise valid requests to overflow the KV cache.
  final int maxTokens;

  const AiCoachModelConfig({this.maxTokens = 4096});
}
