from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing patch target: {label}')
    return text.replace(old, new, 1)


# 1) Make deterministic debrief serializable for the coach context.
path = Path('lib/post_workout_debrief.dart')
text = path.read_text()
text = replace_once(
    text,
    "  String get nextStep => progressionActionLabel(progression);\n}",
    "  String get nextStep => progressionActionLabel(progression);\n\n"
    "  Map<String, dynamic> toContextJson() => {\n"
    "    'exercise_id': exerciseId,\n"
    "    'exercise_name': exerciseName,\n"
    "    'next_step': nextStep,\n"
    "    'progression': progression.toJson(),\n"
    "  };\n}",
    'exercise debrief serializer',
)
text = replace_once(
    text,
    "  int get deloadCount => exercises\n      .where((entry) => entry.progression.action == ProgressionAction.deload)\n      .length;\n}",
    "  int get deloadCount => exercises\n"
    "      .where((entry) => entry.progression.action == ProgressionAction.deload)\n"
    "      .length;\n\n"
    "  Map<String, dynamic> toContextJson() => {\n"
    "    'session_id': session.id,\n"
    "    'previous_comparable_session_id': previousComparableSession?.id,\n"
    "    'total_volume': totalVolume,\n"
    "    'volume_change_percent': volumeChangePercent,\n"
    "    'completed_work_sets': completedWorkSets,\n"
    "    'completed_work_set_delta': completedWorkSetDelta,\n"
    "    'density_kg_per_minute': densityKgPerMinute,\n"
    "    'density_change_percent': densityChangePercent,\n"
    "    'ready_to_progress_count': readyToProgressCount,\n"
    "    'maintain_count': maintainCount,\n"
    "    'deload_count': deloadCount,\n"
    "    'exercises': exercises.map((entry) => entry.toContextJson()).toList(),\n"
    "  };\n}",
    'post workout debrief serializer',
)
path.write_text(text)

# 2) Let chat generation receive an explicit authoritative focus context.
path = Path('lib/ai_coach/local_ai_coach_service.dart')
text = path.read_text()
text = replace_once(
    text,
    "    AiCoachMemory memory = const AiCoachMemory(),\n    List<AiCoachImageInput> newImages = const [],\n  }) async {\n",
    "    AiCoachMemory memory = const AiCoachMemory(),\n"
    "    List<AiCoachImageInput> newImages = const [],\n"
    "    Map<String, dynamic>? focusContext,\n"
    "  }) async {\n",
    'chat focus parameter',
)
text = replace_once(
    text,
    "    final context = contextBuilder.recent(\n      history: history,\n      schedules: schedules,\n      bodyLogs: bodyLogs,\n      profile: profile,\n      memory: memory,\n    );\n\n    final contextJson = jsonEncode(context);",
    "    final context = contextBuilder.recent(\n"
    "      history: history,\n"
    "      schedules: schedules,\n"
    "      bodyLogs: bodyLogs,\n"
    "      profile: profile,\n"
    "      memory: memory,\n"
    "    );\n"
    "    if (focusContext != null && focusContext.isNotEmpty) {\n"
    "      context['focus_context'] = focusContext;\n"
    "    }\n\n"
    "    final contextJson = jsonEncode(context);",
    'chat context injection',
)
text = replace_once(
    text,
    "Answer naturally as a supportive but honest coach. Use the context to inform your answers.\nNever invent workout data, loads, reps, or medical information.\nKeep responses concise and practical.",
    "Answer naturally as a supportive but honest coach. Use the context to inform your answers.\n"
    "If focus_context exists, it is the authoritative scope for the current discussion: use the exact target session and deterministic debrief values first, then enrich the explanation with the broader training context. Do not contradict deterministic metrics or recommendations without explicitly explaining the evidence and uncertainty.\n"
    "Never invent workout data, loads, reps, or medical information.\n"
    "Keep responses concise and practical.",
    'focus prompt contract',
)
path.write_text(text)

# 3) Pass launch context through the data-loading entry screen.
path = Path('lib/screens/ai_coach_entry.dart')
text = path.read_text()
text = replace_once(
    text,
    "import '../app_data_store.dart';\nimport 'ai_coach.dart';",
    "import '../ai_coach/ai_coach_handoff.dart';\nimport '../app_data_store.dart';\nimport 'ai_coach.dart';",
    'entry import',
)
text = replace_once(
    text,
    "class AiCoachEntryScreen extends StatefulWidget {\n  const AiCoachEntryScreen({super.key});",
    "class AiCoachEntryScreen extends StatefulWidget {\n"
    "  final AiCoachLaunchContext? launchContext;\n\n"
    "  const AiCoachEntryScreen({super.key, this.launchContext});",
    'entry launch field',
)
text = replace_once(
    text,
    "          bodyLogs: bundle.bodyLogs,\n        );",
    "          bodyLogs: bundle.bodyLogs,\n          launchContext: widget.launchContext,\n        );",
    'entry forward context',
)
path.write_text(text)

# 4) Make the coach auto-start a dedicated focused conversation and retain the
# focus context for follow-up messages in that conversation.
path = Path('lib/screens/ai_coach.dart')
text = path.read_text()
text = replace_once(
    text,
    "import '../ai_coach/ai_coach_memory.dart';\n",
    "import '../ai_coach/ai_coach_handoff.dart';\nimport '../ai_coach/ai_coach_memory.dart';\n",
    'coach handoff import',
)
text = replace_once(
    text,
    "  final AiPlanActionService planActionService;\n",
    "  final AiPlanActionService planActionService;\n  final AiCoachLaunchContext? launchContext;\n",
    'coach launch field',
)
text = replace_once(
    text,
    "    this.modelInstaller = const FlutterGemmaAiCoachModelInstaller(),\n    this.planActionService = const AiPlanActionService(),\n  });",
    "    this.modelInstaller = const FlutterGemmaAiCoachModelInstaller(),\n"
    "    this.planActionService = const AiPlanActionService(),\n"
    "    this.launchContext,\n"
    "  });",
    'coach launch constructor',
)
text = replace_once(
    text,
    "  String? _errorMessage;\n",
    "  String? _errorMessage;\n"
    "  Map<String, dynamic>? _focusContext;\n"
    "  bool _profileLoaded = false;\n"
    "  bool _conversationsLoaded = false;\n"
    "  bool _modelChecked = false;\n"
    "  bool _launchStarted = false;\n",
    'coach handoff state',
)
text = replace_once(
    text,
    "  void initState() {\n    super.initState();\n    _refreshModelState();",
    "  void initState() {\n"
    "    super.initState();\n"
    "    _focusContext = widget.launchContext?.focusContext;\n"
    "    _refreshModelState();",
    'coach init focus',
)
text = replace_once(
    text,
    "    setState(() {\n      _profile = profile;\n      _memory = memory;\n    });\n  }",
    "    setState(() {\n"
    "      _profile = profile;\n"
    "      _memory = memory;\n"
    "      _profileLoaded = true;\n"
    "    });\n"
    "    _maybeStartLaunchHandoff();\n"
    "  }",
    'profile loaded handoff',
)
text = replace_once(
    text,
    "    setState(() {\n      _allConversations = all;\n      if (all.isNotEmpty) {\n        _conversation = all.first;\n      }\n    });\n  }",
    "    setState(() {\n"
    "      _allConversations = all;\n"
    "      if (all.isNotEmpty) {\n"
    "        _conversation = all.first;\n"
    "      }\n"
    "      _conversationsLoaded = true;\n"
    "    });\n"
    "    _maybeStartLaunchHandoff();\n"
    "  }",
    'conversations loaded handoff',
)
text = replace_once(
    text,
    "      setState(() {\n        _isModelInstalled = isInstalled;\n        _isCheckingModel = false;\n      });",
    "      setState(() {\n"
    "        _isModelInstalled = isInstalled;\n"
    "        _isCheckingModel = false;\n"
    "        _modelChecked = true;\n"
    "      });\n"
    "      _maybeStartLaunchHandoff();",
    'model success handoff',
)
text = replace_once(
    text,
    "        _isModelInstalled = false;\n        _isCheckingModel = false;\n        _errorMessage =",
    "        _isModelInstalled = false;\n"
    "        _isCheckingModel = false;\n"
    "        _modelChecked = true;\n"
    "        _errorMessage =",
    'model error checked flag',
)
text = replace_once(
    text,
    "        _isModelInstalled = true;\n        _downloadProgress = 100;\n      });\n      ScaffoldMessenger.of(context).showSnackBar(",
    "        _isModelInstalled = true;\n"
    "        _downloadProgress = 100;\n"
    "        _modelChecked = true;\n"
    "      });\n"
    "      _maybeStartLaunchHandoff();\n"
    "      ScaffoldMessenger.of(context).showSnackBar(",
    'download handoff',
)
text = replace_once(
    text,
    "  Future<void> _startNewConversation() async {\n    final conversation = ChatConversation(",
    "  Future<void> _startNewConversation() async {\n"
    "    _launchStarted = true;\n"
    "    _focusContext = null;\n"
    "    final conversation = ChatConversation(",
    'new conversation clears focus',
)
text = replace_once(
    text,
    "  Future<void> _switchConversation(ChatConversation conversation) async {\n    setState(() {",
    "  Future<void> _switchConversation(ChatConversation conversation) async {\n"
    "    _launchStarted = true;\n"
    "    _focusContext = null;\n"
    "    setState(() {",
    'switch clears focus',
)
insert_marker = "  Future<void> _pickImages() async {"
if insert_marker not in text:
    raise SystemExit('missing patch target: handoff method insertion')
handoff_method = r'''  Future<void> _maybeStartLaunchHandoff() async {
    final launch = widget.launchContext;
    if (launch == null ||
        _launchStarted ||
        !_profileLoaded ||
        !_conversationsLoaded ||
        !_modelChecked ||
        _isRunning) {
      return;
    }

    if (!_isModelInstalled) {
      if (_textController.text.isEmpty) {
        _textController.text = launch.userPrompt;
        if (mounted) setState(() {});
      }
      return;
    }

    _launchStarted = true;
    final conversation = ChatConversation(
      id: generateConversationId(),
      title: launch.conversationTitle,
    );
    if (!mounted) return;
    setState(() {
      _conversation = conversation;
      _focusContext = launch.focusContext;
      _pendingImages = [];
      _errorMessage = null;
      _textController.text = launch.userPrompt;
    });
    await _saveAndRefresh(conversation);
    if (!mounted) return;
    await _sendMessage();
  }

'''
text = text.replace(insert_marker, handoff_method + insert_marker, 1)
text = replace_once(
    text,
    "        newImages: userMessage.hasImages\n            ? userMessage.imageBytes\n                  .map((bytes) => AiCoachImageInput(label: '', bytes: bytes))\n                  .toList()\n            : [],\n      );",
    "        newImages: userMessage.hasImages\n"
    "            ? userMessage.imageBytes\n"
    "                  .map((bytes) => AiCoachImageInput(label: '', bytes: bytes))\n"
    "                  .toList()\n"
    "            : [],\n"
    "        focusContext: _focusContext,\n"
    "      );",
    'send focus context',
)
text = replace_once(
    text,
    "          if (_pendingImages.isNotEmpty)\n            _PendingImagesBar(",
    "          if (_focusContext != null)\n"
    "            Container(\n"
    "              key: const ValueKey('ai-focus-context-banner'),\n"
    "              width: double.infinity,\n"
    "              margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),\n"
    "              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),\n"
    "              decoration: BoxDecoration(\n"
    "                color: colorScheme.primaryContainer.withValues(alpha: 0.55),\n"
    "                borderRadius: BorderRadius.circular(16),\n"
    "              ),\n"
    "              child: Row(\n"
    "                children: [\n"
    "                  Icon(Icons.insights, size: 18, color: colorScheme.primary),\n"
    "                  const SizedBox(width: 8),\n"
    "                  Expanded(\n"
    "                    child: Text(\n"
    "                      'Contesto Smart Debrief attivo: seduta, storico e analytics sono disponibili al Coach.',\n"
    "                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),\n"
    "                    ),\n"
    "                  ),\n"
    "                ],\n"
    "              ),\n"
    "            ),\n"
    "          if (_pendingImages.isNotEmpty)\n"
    "            _PendingImagesBar(",
    'focus banner',
)
path.write_text(text)

# 5) Add the one-tap handoff from the post-workout summary.
path = Path('lib/screens/session_summary.dart')
text = path.read_text()
text = replace_once(
    text,
    "import '../models/exercise.dart';\n",
    "import '../ai_coach/ai_coach_handoff.dart';\nimport '../models/exercise.dart';\n",
    'summary handoff import',
)
text = replace_once(
    text,
    "import '../workout_progression_analytics.dart';\n",
    "import '../workout_progression_analytics.dart';\nimport 'ai_coach_entry.dart';\n",
    'summary entry import',
)
text = replace_once(
    text,
    "  @override\n  Widget build(BuildContext context) {",
    "  Future<void> _openCoachDebrief(PostWorkoutDebrief debrief) async {\n"
    "    final launchContext = AiCoachLaunchContext.postWorkout(\n"
    "      session: widget.session,\n"
    "      history: widget.previousHistory,\n"
    "      debrief: debrief,\n"
    "    );\n"
    "    await Navigator.push<void>(\n"
    "      context,\n"
    "      MaterialPageRoute(\n"
    "        builder: (_) => AiCoachEntryScreen(launchContext: launchContext),\n"
    "      ),\n"
    "    );\n"
    "  }\n\n"
    "  @override\n"
    "  Widget build(BuildContext context) {",
    'summary open coach method',
)
old_bottom = r'''      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Chiudi'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSharing ? null : _shareSummary,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Condividi'),
                ),
              ),
            ],
          ),
        ),
      ),'''
new_bottom = r'''      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('ask-coach-debrief'),
                  onPressed: () => _openCoachDebrief(debrief),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('Chiedi al Coach'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Chiudi'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSharing ? null : _shareSummary,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Condividi'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),'''
text = replace_once(text, old_bottom, new_bottom, 'summary coach button')
path.write_text(text)
