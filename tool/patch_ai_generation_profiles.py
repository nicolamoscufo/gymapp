from pathlib import Path

path = Path('lib/ai_coach/local_llm_engine.dart')
text = path.read_text()

import_anchor = "import 'ai_coach_model_config.dart';\n"
if "import 'ai_coach_generation_profile.dart';" not in text:
    text = text.replace(
        import_anchor,
        "import 'ai_coach_generation_profile.dart';\n" + import_anchor,
        1,
    )


def patch_between(source: str, start_marker: str, end_marker: str, profile_name: str, old_temp: str, old_topk: str = '40') -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    segment = source[start:end]

    chat_anchor = '    InferenceChat? chat;\n'
    if f'    final profile = AiCoachGenerationProfiles.{profile_name};\n' not in segment:
        segment = segment.replace(
            chat_anchor,
            f'    final profile = AiCoachGenerationProfiles.{profile_name};\n' + chat_anchor,
            1,
        )

    old = f'''      chat = await model.createChat(\n        temperature: {old_temp},\n        topK: {old_topk},\n        topP: 0.9,\n        tokenBuffer: 1024,\n'''
    new = '''      chat = await model.createChat(\n        temperature: profile.temperature,\n        randomSeed: profile.randomSeed,\n        topK: profile.topK,\n        topP: profile.topP,\n        tokenBuffer: profile.tokenBuffer,\n        maxOutputTokens: profile.maxOutputTokens,\n'''
    if old not in segment:
        raise RuntimeError(f'createChat anchor missing in {start_marker}')
    segment = segment.replace(old, new, 1)
    return source[:start] + segment + source[end:]


text = patch_between(
    text,
    '  Future<String> generateStructuredJsonWithImages(',
    '  @override\n  Future<String> generateChatText(',
    'visionStructured',
    '0.2',
)

text = patch_between(
    text,
    '  Future<String> generateChatText({',
    '  @override\n  Future<String> generateText(',
    'chat',
    '0.3',
)

start = text.index('  Future<String> generateText(String prompt) async {')
end = text.index('  String _responseText(', start)
segment = text[start:end]
chat_anchor = '    InferenceChat? chat;\n'
profile_line = (
    '    final profile = '\
    'AiCoachGenerationProfiles.forStructuredPrompt(prompt);\n'
)
if profile_line not in segment:
    segment = segment.replace(chat_anchor, profile_line + chat_anchor, 1)
old = '''      chat = await model.createChat(\n        temperature: 0.2,\n        topK: 40,\n        topP: 0.9,\n        tokenBuffer: 1024,\n'''
new = '''      chat = await model.createChat(\n        temperature: profile.temperature,\n        randomSeed: profile.randomSeed,\n        topK: profile.topK,\n        topP: profile.topP,\n        tokenBuffer: profile.tokenBuffer,\n        maxOutputTokens: profile.maxOutputTokens,\n'''
if old not in segment:
    raise RuntimeError('generateText createChat anchor missing')
segment = segment.replace(old, new, 1)
text = text[:start] + segment + text[end:]

path.write_text(text)
