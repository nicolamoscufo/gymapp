import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'ai_coach_models.dart';
import 'ai_coach_generation_profile.dart';
import 'ai_coach_model_config.dart';
import 'ai_coach_model_manager.dart';
import 'chat_conversation.dart';

abstract class LocalLlmEngine {
  Future<void> initialize();

  Future<String> generateText(String prompt);

  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  );

  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  );

  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  });

  Future<void> dispose();
}

class AiCoachModelNotInstalledException implements Exception {
  final String message;

  const AiCoachModelNotInstalledException(this.message);

  @override
  String toString() => message;
}

class HeuristicLocalLlmEngine implements LocalLlmEngine {
  const HeuristicLocalLlmEngine();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> generateText(String prompt) async {
    return await generateStructuredJson(prompt, const {});
  }

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async {
    final lastUser = messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => ChatMessage(role: 'user', content: ''),
    );
    final text = lastUser.content.isNotEmpty
        ? lastUser.content
        : 'How can I help with your training?';
    return 'Based on your training data, $text. As your local AI coach, I recommend keeping consistent with your current program. Focus on progressive overload and proper recovery.';
  }

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    final task = _taskFromPrompt(prompt);
    final context = _contextFromPrompt(prompt);
    final workouts = _workouts(context);
    final metrics = Map<String, dynamic>.from(context['metrics'] as Map? ?? {});
    final notes = _notesFromContext(context);
    final themes = _themesFor(notes);
    final warnings = _warningNotes(notes);

    final result = switch (task) {
      'workout_recap' => _workoutRecap(workouts, metrics, notes, warnings),
      'weekly_report' => _weeklyReport(workouts, metrics, themes, warnings),
      'weak_point_analysis' => _weakPoints(workouts, metrics, warnings),
      'notes_summary' => _notesSummary(notes, themes, warnings),
      'suggested_adjustments' => _suggestions(workouts, metrics, warnings),
      'body_photo_analysis' => _photoAnalysisPlaceholder(),
      _ => {'summary': 'Local analysis is not available.'},
    };
    return jsonEncode(result);
  }

  @override
  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  ) async {
    return jsonEncode({
      'summary': images.length < 2
          ? 'At least two photos are required to compare visual changes.'
          : 'Simulated local photo comparison: use the installed Gemma model for a real visual assessment.',
      'visible_changes': images.length < 2
          ? const <String>[]
          : ['Uploaded photos: ${images.map((image) => image.label).join(', ')}'],
      'improved_areas': const <String>[],
      'unchanged_areas': const <String>[],
      'cautions': const [
        'Always compare lighting, pose, distance, and pump before concluding there are real differences.',
      ],
      'evidence': images.map((image) => image.label).toList(),
      'next_checkin_tips': const [
        'Take the next photos with the same lighting, pose, distance, time of day, and pump state.',
      ],
    });
  }

  String _taskFromPrompt(String prompt) {
    return RegExp(r'TASK:\s*([a-z_]+)').firstMatch(prompt)?.group(1) ?? '';
  }

  Map<String, dynamic> _contextFromPrompt(String prompt) {
    final match = RegExp(
      r'<context_json>\s*([\s\S]*?)\s*</context_json>',
    ).firstMatch(prompt);
    if (match == null) return const {};
    final decoded = jsonDecode(match.group(1)!) as Object?;
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  }

  List<Map<String, dynamic>> _workouts(Map<String, dynamic> context) {
    return (context['workouts'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  List<String> _notesFromContext(Map<String, dynamic> context) {
    final directNotes = (context['notes'] as List? ?? const [])
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    if (directNotes.isNotEmpty) return directNotes;

    final notes = <String>[];
    for (final workout in _workouts(context)) {
      for (final exercise in workout['exercises'] as List? ?? const []) {
        final exerciseMap = Map<String, dynamic>.from(exercise as Map);
        final exerciseNote = exerciseMap['notes']?.toString().trim() ?? '';
        if (exerciseNote.isNotEmpty) {
          notes.add('${exerciseMap['name']}: $exerciseNote');
        }
        for (final set in exerciseMap['sets'] as List? ?? const []) {
          final setMap = Map<String, dynamic>.from(set as Map);
          final setNote = setMap['notes']?.toString().trim() ?? '';
          if (setNote.isNotEmpty) {
            notes.add('${exerciseMap['name']}: $setNote');
          }
        }
      }
    }
    return notes;
  }

  Map<String, dynamic> _workoutRecap(
    List<Map<String, dynamic>> workouts,
    Map<String, dynamic> metrics,
    List<String> notes,
    List<String> warnings,
  ) {
    final workout = workouts.isEmpty
        ? const <String, dynamic>{}
        : workouts.last;
    final name = workout['name']?.toString() ?? 'workout';
    final volume = _num(metrics['total_volume']);
    final sessions = _int(metrics['sessions']);
    return {
      'summary': sessions == 0
          ? 'There is not enough data for a detailed recap.'
          : '$name completed with ${_format(volume)} kg of estimated volume.',
      'positive_points': [
        if (volume > 0) 'You logged useful training volume.',
        if (notes.isNotEmpty)
          'Your notes provide context for the next session.',
      ],
      'negative_points': [
        if (warnings.isNotEmpty)
          'There are discomfort or fatigue notes that should be managed carefully.',
        if (volume == 0) 'No completed work sets were found.',
      ],
      'note_summary': notes.isEmpty
          ? 'No relevant notes were logged.'
          : _compactNotes(notes),
      'warnings': warnings
          .map(
            (note) =>
                'Caution note: $note. This is not a diagnosis; review technique and recovery.',
          )
          .toList(),
      'next_session_focus': [
        'Only keep progressing if technique and recovery are stable.',
        if (warnings.isNotEmpty)
          'Do not increase loads aggressively on the flagged movements.',
      ],
    };
  }

  Map<String, dynamic> _weeklyReport(
    List<Map<String, dynamic>> workouts,
    Map<String, dynamic> metrics,
    List<String> themes,
    List<String> warnings,
  ) {
    final sessions = _int(metrics['sessions']);
    final volume = _num(metrics['total_volume']);
    final best = _bestExercise(metrics);
    final weakGroups = _weakGroups(metrics);
    return {
      'summary': sessions == 0
          ? 'No completed sessions were found this week.'
          : '$sessions completed sessions, estimated volume ${_format(volume)} kg.',
      'sessions_completed': sessions,
      'main_improvements': [
        if (best.isNotEmpty) '$best had the most volume in this period.',
      ],
      'possible_weak_points': weakGroups,
      'stalled_exercises': _stalledExercises(workouts),
      'best_progressions': [if (best.isNotEmpty) best],
      'recovery_notes': [
        if (themes.contains('fatigue'))
          'Recurring fatigue in notes: check recovery and sleep.',
        if (warnings.isNotEmpty)
          'Caution notes are present: avoid diagnoses and review technique.',
      ],
      'practical_suggestions': [
        'Confirm or edit loads only from the plan, after manual review.',
        if (weakGroups.isNotEmpty)
          'Consider balancing volume across less-trained muscle groups.',
      ],
    };
  }

  Map<String, dynamic> _weakPoints(
    List<Map<String, dynamic>> workouts,
    Map<String, dynamic> metrics,
    List<String> warnings,
  ) {
    final points = <Map<String, dynamic>>[];
    for (final group in _weakGroups(metrics)) {
      points.add({
        'area': group,
        'reason': 'Low volume or frequency in the analyzed period.',
        'evidence': ['Recent muscle distribution is unbalanced.'],
        'suggestion':
            'Consider adding volume only if recovery and technique are good.',
      });
    }
    for (final note in warnings.take(3)) {
      points.add({
        'area': 'Technique/recovery caution',
        'reason':
            'Recurring note potentially related to discomfort or fatigue.',
        'evidence': [note],
        'suggestion':
            'Reduce progression aggressiveness and consult a professional if it persists.',
      });
    }
    if (points.isEmpty && workouts.length >= 2) {
      points.add({
        'area': 'Progression',
        'reason': 'No obvious weak point from the compact data.',
        'evidence': ['Recent history has no obvious critical notes.'],
        'suggestion': 'Keep monitoring loads, RIR/RPE, and exercise notes.',
      });
    }
    return {'weak_points': points};
  }

  Map<String, dynamic> _notesSummary(
    List<String> notes,
    List<String> themes,
    List<String> warnings,
  ) {
    return {
      'summary': notes.isEmpty
          ? 'No text notes are available for this period.'
          : _compactNotes(notes),
      'recurring_themes': themes,
      'important_notes': warnings.isEmpty
          ? notes.take(5).toList()
          : warnings.take(5).toList(),
      'sentiment': warnings.isNotEmpty
          ? 'mixed'
          : themes.contains('good pump') || themes.contains('good energy')
          ? 'positive'
          : 'neutral',
    };
  }

  Map<String, dynamic> _suggestions(
    List<Map<String, dynamic>> workouts,
    Map<String, dynamic> metrics,
    List<String> warnings,
  ) {
    final suggestions = <Map<String, dynamic>>[];
    final best = _bestExercise(metrics);
    if (best.isNotEmpty) {
      suggestions.add({
        'type': 'load_progression',
        'target': best,
        'suggestion':
            'Consider a small increase only if the latest execution was stable.',
        'reason': 'Exercise with good recent volume.',
        'evidence': ['Recent volume is higher than other exercises.'],
        'confidence': 'medium',
        'requires_user_confirmation': true,
      });
    }
    for (final note in warnings.take(2)) {
      suggestions.add({
        'type': 'technique_review',
        'target': 'Exercise with caution note',
        'suggestion':
            'Keep or reduce the load and review technique before progressing.',
        'reason': 'Note potentially related to discomfort or fatigue.',
        'evidence': [note],
        'confidence': 'medium',
        'requires_user_confirmation': true,
      });
    }
    if (suggestions.isEmpty && workouts.isNotEmpty) {
      suggestions.add({
        'type': 'recovery',
        'target': 'Overall plan',
        'suggestion':
            'Keep the current progression and continue logging RIR/RPE.',
        'reason': 'There are no strong signals to change the plan.',
        'evidence': ['Recent history has no obvious critical issues.'],
        'confidence': 'low',
        'requires_user_confirmation': true,
      });
    }
    return {'suggestions': suggestions};
  }

  Map<String, dynamic> _photoAnalysisPlaceholder() {
    return const {
      'summary':
          'Photo analysis is available only with a multimodal Gemma model installed.',
      'visible_changes': <String>[],
      'improved_areas': <String>[],
      'unchanged_areas': <String>[],
      'cautions': <String>[
        'Compare photos only when pose, lighting, distance, and pump are similar.',
      ],
      'evidence': <String>[],
      'next_checkin_tips': <String>[
        'Repeat photos with the same setup every 2-4 weeks.',
      ],
    };
  }

  List<String> _themesFor(List<String> notes) {
    final themes = <String>{};
    final joined = notes.join(' ').toLowerCase();
    if (_containsAny(joined, [
      'stanco',
      'fatica',
      'tired',
      'low energy',
      'scarico',
    ])) {
      themes.add('fatigue');
    }
    if (_containsAny(joined, [
      'pump',
      'stimolo',
      'sentito bene',
      'good pump',
    ])) {
      themes.add('good pump');
    }
    if (_containsAny(joined, ['spalla', 'shoulder'])) {
      themes.add('shoulder/discomfort');
    }
    if (_containsAny(joined, ['dolore', 'pain', 'fastidio', 'discomfort'])) {
      themes.add('discomfort');
    }
    if (_containsAny(joined, ['unstable', 'bad technique'])) {
      themes.add('technique');
    }
    if (_containsAny(joined, ['non sento', 'mind-muscle', 'stimolo scarso'])) {
      themes.add('mind-muscle connection');
    }
    if (themes.isEmpty && notes.isNotEmpty) themes.add('misc notes');
    return themes.toList();
  }

  List<String> _warningNotes(List<String> notes) {
    return notes.where((note) {
      final lower = note.toLowerCase();
      return _containsAny(lower, [
        'dolore',
        'pain',
        'fastidio',
        'spalla',
        'shoulder',
        'gomito',
        'knee',
        'ginocchio',
        'troppo stanco',
        'low energy',
      ]);
    }).toList();
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  String _compactNotes(List<String> notes) {
    return notes.take(4).join(' | ');
  }

  List<String> _weakGroups(Map<String, dynamic> metrics) {
    final raw = metrics['muscle_group_volume'];
    if (raw is! Map || raw.isEmpty) return const [];
    final entries = raw.entries
        .map((entry) => MapEntry(entry.key.toString(), _num(entry.value)))
        .where((entry) => entry.value > 0)
        .toList();
    if (entries.length < 2) return const [];
    entries.sort((a, b) => a.value.compareTo(b.value));
    final max = entries.last.value;
    return entries
        .where((entry) => entry.value < max * 0.35)
        .map((entry) => entry.key)
        .toList();
  }

  List<String> _stalledExercises(List<Map<String, dynamic>> workouts) {
    final byExercise = <String, List<double>>{};
    for (final workout in workouts) {
      for (final exercise in workout['exercises'] as List? ?? const []) {
        final exerciseMap = Map<String, dynamic>.from(exercise as Map);
        final name = exerciseMap['name'].toString();
        var volume = 0.0;
        for (final set in exerciseMap['sets'] as List? ?? const []) {
          final setMap = Map<String, dynamic>.from(set as Map);
          if (setMap['completed'] == true && setMap['warmup'] != true) {
            volume += _num(setMap['weight']) * _num(setMap['reps']);
          }
        }
        byExercise.putIfAbsent(name, () => []).add(volume);
      }
    }
    return byExercise.entries
        .where(
          (entry) => entry.value.length >= 3 && entry.value.toSet().length <= 1,
        )
        .map((entry) => entry.key)
        .toList();
  }

  String _bestExercise(Map<String, dynamic> metrics) {
    final raw = metrics['exercise_volume'];
    if (raw is! Map || raw.isEmpty) return '';
    final entries = raw.entries
        .map((entry) => MapEntry(entry.key.toString(), _num(entry.value)))
        .toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  num _num(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _int(Object? value) => _num(value).toInt();

  String _format(num value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }
}

class FlutterGemmaLocalLlmEngine implements LocalLlmEngine {
  final AiCoachModelConfig config;
  final AiCoachModelInstaller modelInstaller;

  const FlutterGemmaLocalLlmEngine({
    this.config = const AiCoachModelConfig(),
    this.modelInstaller = const FlutterGemmaAiCoachModelInstaller(),
  });

  static InferenceModel? _model;
  static bool _isReady = false;
  static bool _modelSupportsImages = false;

  @override
  Future<void> initialize() async {
    await _ensureModel(supportImage: false);
  }

  Future<void> _ensureModel({required bool supportImage}) async {
    if (_isReady && _model != null && (!supportImage || _modelSupportsImages)) {
      return;
    }

    if (_model != null && supportImage && !_modelSupportsImages) {
      await _model?.close();
      _model = null;
      _isReady = false;
    }

    final isInstalled = await modelInstaller.isInstalled();
    if (!isInstalled) {
      throw AiCoachModelNotInstalledException(
        'Download ${modelInstaller.modelName} (${modelInstaller.modelSizeLabel}) before starting the local AI coach.',
      );
    }

    await modelInstaller.activateInstalledModel();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: config.maxTokens,
      supportImage: supportImage,
      maxNumImages: supportImage ? 4 : null,
      maxConcurrentSessions: 1,
      enableSpeculativeDecoding: true,
    );
    _modelSupportsImages = supportImage;
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _modelSupportsImages = false;
    _isReady = false;
  }

  @override
  Future<String> generateStructuredJson(
    String prompt,
    Map<String, dynamic> schema,
  ) async {
    return generateText(prompt);
  }

  @override
  Future<String> generateStructuredJsonWithImages(
    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
  ) async {
    await _ensureModel(supportImage: true);
    final model = _model;
    if (model == null) {
      throw const AiCoachModelNotInstalledException(
        'Local AI model is not ready.',
      );
    }

    final profile = AiCoachGenerationProfiles.visionStructured;
    InferenceChat? chat;
    try {
      chat = await model.createChat(
        temperature: profile.temperature,
        randomSeed: profile.randomSeed,
        topK: profile.topK,
        topP: profile.topP,
        tokenBuffer: profile.tokenBuffer,
        maxOutputTokens: profile.maxOutputTokens,
        supportImage: true,
        supportAudio: false,
        supportsFunctionCalls: false,
        isThinking: false,
        modelType: ModelType.gemma4,
        systemInstruction:
            'You are a local fitness coach. Compare images only for visible physique progress, with no diagnoses or sensitive inferences. Respond only with valid JSON.',
      );
      await chat.addQueryChunk(
        Message.withImages(
          text: prompt,
          imageBytes: images.map((image) => image.bytes).toList(),
          isUser: true,
        ),
      );
      final response = await chat.generateChatResponse();
      return _responseText(response).trim();
    } finally {
      await chat?.close();
    }
  }

  @override
  Future<String> generateChatText({
    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
  }) async {
    final hasImages = newImages.isNotEmpty || messages.any((m) => m.hasImages);
    await _ensureModel(supportImage: hasImages);
    final model = _model;
    if (model == null) {
      throw const AiCoachModelNotInstalledException(
        'Local AI model is not ready.',
      );
    }

    final profile = AiCoachGenerationProfiles.chat;
    InferenceChat? chat;
    try {
      chat = await model.createChat(
        temperature: profile.temperature,
        randomSeed: profile.randomSeed,
        topK: profile.topK,
        topP: profile.topP,
        tokenBuffer: profile.tokenBuffer,
        maxOutputTokens: profile.maxOutputTokens,
        supportImage: hasImages,
        supportAudio: false,
        supportsFunctionCalls: false,
        isThinking: false,
        modelType: ModelType.gemma4,
        systemInstruction: systemPrompt,
      );

      final lastUserIndex = messages.lastIndexWhere((m) => m.role == 'user');

      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        final isLastUser = i == lastUserIndex;
        if (msg.role == 'user') {
          if (msg.hasImages) {
            await chat.addQueryChunk(
              Message.withImages(
                text: msg.content,
                imageBytes: msg.imageBytes,
                isUser: true,
              ),
            );
          } else {
            await chat.addQueryChunk(
              Message.text(text: msg.content, isUser: true),
            );
          }
          if (!isLastUser) {
            await chat.generateChatResponse();
          }
        } else {
          await chat.addQueryChunk(
            Message.text(text: msg.content, isUser: false),
          );
          await chat.generateChatResponse();
        }
      }

      if (newImages.isNotEmpty) {
        final lastUserMsg = messages.isNotEmpty
            ? messages.lastWhere(
                (m) => m.role == 'user',
                orElse: () => ChatMessage(role: 'user', content: ''),
              )
            : ChatMessage(role: 'user', content: '');
        await chat.addQueryChunk(
          Message.withImages(
            text: lastUserMsg.content,
            imageBytes: newImages.map((i) => i.bytes).toList(),
            isUser: true,
          ),
        );
      }

      final response = await chat.generateChatResponse();
      return _responseText(response).trim();
    } finally {
      await chat?.close();
    }
  }

  @override
  Future<String> generateText(String prompt) async {
    await _ensureModel(supportImage: false);
    final model = _model;
    if (model == null) {
      throw const AiCoachModelNotInstalledException(
        'Local AI model is not ready.',
      );
    }

    final profile = AiCoachGenerationProfiles.forStructuredPrompt(prompt);
    InferenceChat? chat;
    try {
      chat = await model.createChat(
        temperature: profile.temperature,
        randomSeed: profile.randomSeed,
        topK: profile.topK,
        topP: profile.topP,
        tokenBuffer: profile.tokenBuffer,
        maxOutputTokens: profile.maxOutputTokens,
        supportImage: false,
        supportAudio: false,
        supportsFunctionCalls: false,
        isThinking: false,
        modelType: ModelType.gemma4,
        systemInstruction:
            'You are a local fitness coach. Use only the provided data, respond with valid JSON, and do not make medical diagnoses.',
      );
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await chat.generateChatResponse();
      return _responseText(response).trim();
    } finally {
      await chat?.close();
    }
  }

  String _responseText(ModelResponse response) {
    return switch (response) {
      TextResponse(:final token) => token,
      ThinkingResponse(:final content) => content,
      FunctionCallResponse(:final name, :final args) => jsonEncode({
        'function': name,
        'arguments': args,
      }),
      ParallelFunctionCallResponse(:final calls) => jsonEncode({
        'calls': calls
            .map((call) => {'function': call.name, 'arguments': call.args})
            .toList(),
      }),
    };
  }
}
