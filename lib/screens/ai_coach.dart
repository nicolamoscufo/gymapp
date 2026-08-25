import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ai_coach/ai_coach_memory.dart';
import '../ai_coach/ai_plan_action_service.dart';
import '../app_data_store.dart';
import '../ai_coach/ai_coach_model_manager.dart';
import '../ai_coach/ai_coach_models.dart';
import '../ai_coach/ai_coach_user_profile.dart';
import '../ai_coach/chat_conversation.dart';
import '../ai_coach/local_ai_coach_service.dart';
import '../models/body_log.dart';
import '../models/schedule.dart';
import '../models/workout.dart';

class AiCoachScreen extends StatefulWidget {
  final List<WorkoutSession> history;
  final List<Schedule> schedules;
  final List<BodyLog> bodyLogs;
  final LocalAiCoachService service;
  final AiCoachModelInstaller modelInstaller;
  final AiPlanActionService planActionService;

  const AiCoachScreen({
    super.key,
    required this.history,
    required this.schedules,
    this.bodyLogs = const [],
    this.service = const LocalAiCoachService(),
    this.modelInstaller = const FlutterGemmaAiCoachModelInstaller(),
    this.planActionService = const AiPlanActionService(),
  });

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatConversationStore _conversationStore =
      const ChatConversationStore();
  final AiCoachProfileStore _profileStore = const AiCoachProfileStore();
  final AiCoachMemoryStore _memoryStore = const AiCoachMemoryStore();

  AiCoachUserProfile _profile = const AiCoachUserProfile();
  AiCoachMemory _memory = const AiCoachMemory();
  ChatConversation _conversation = ChatConversation(
    id: generateConversationId(),
    title: 'Nuova chat',
  );
  List<ChatConversation> _allConversations = [];
  List<AiCoachImageInput> _pendingImages = [];
  bool _isRunning = false;
  bool _isAnalyzingPlan = false;
  bool _isCheckingModel = true;
  bool _isModelInstalled = false;
  bool _isDownloadingModel = false;
  int? _downloadProgress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _refreshModelState();
    _loadProfileAndMemory();
    _loadConversations();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileAndMemory() async {
    final profile = await _profileStore.load();
    final memory = await _memoryStore.load();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _memory = memory;
    });
  }

  Future<void> _loadConversations() async {
    final all = await _conversationStore.loadAll();
    if (!mounted) return;
    setState(() {
      _allConversations = all;
      if (all.isNotEmpty) {
        _conversation = all.first;
      }
    });
  }

  Future<void> _refreshModelState() async {
    try {
      final isInstalled = await widget.modelInstaller.isInstalled();
      if (!mounted) return;
      setState(() {
        _isModelInstalled = isInstalled;
        _isCheckingModel = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isModelInstalled = false;
        _isCheckingModel = false;
        _errorMessage =
            'Unable to check the local model. Verify the platform and dependencies.';
      });
    }
  }

  Future<void> _downloadModel() async {
    if (_isDownloadingModel) return;
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = 0;
      _errorMessage = null;
    });

    try {
      await widget.modelInstaller.install(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress.clamp(0, 100));
        },
      );
      if (!mounted) return;
      setState(() {
        _isModelInstalled = true;
        _downloadProgress = 100;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.modelInstaller.modelName} is ready.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage =
            'Model download failed. Check your connection and free storage space.',
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloadingModel = false);
      }
    }
  }

  Future<void> _startNewConversation() async {
    final conversation = ChatConversation(
      id: generateConversationId(),
      title: 'Nuova chat',
    );
    setState(() {
      _conversation = conversation;
      _pendingImages = [];
      _errorMessage = null;
    });
    await _saveAndRefresh(conversation);
  }

  Future<void> _switchConversation(ChatConversation conversation) async {
    setState(() {
      _conversation = conversation;
      _pendingImages = [];
      _errorMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _deleteConversation(ChatConversation conversation) async {
    await _conversationStore.deleteConversation(conversation.id);
    final all = await _conversationStore.loadAll();
    if (!mounted) return;
    setState(() {
      _allConversations = all;
      if (_conversation.id == conversation.id) {
        _conversation = all.isNotEmpty
            ? all.first
            : ChatConversation(
                id: generateConversationId(),
                title: 'Nuova chat',
              );
      }
    });
  }

  Future<void> _saveAndRefresh(ChatConversation conversation) async {
    final saved = await _conversationStore.saveConversation(conversation);
    final all = await _conversationStore.loadAll();
    if (!mounted) return;
    setState(() {
      _conversation = saved;
      _allConversations = all;
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final images = files
        .where((file) => file.bytes != null)
        .take(4)
        .map((file) => AiCoachImageInput(label: file.name, bytes: file.bytes!))
        .toList();
    if (images.isEmpty) return;
    setState(() {
      _pendingImages = [..._pendingImages, ...images].take(4).toList();
    });
  }

  void _removePendingImage(int index) {
    setState(() {
      _pendingImages.removeAt(index);
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final hasText = text.isNotEmpty;
    final hasImages = _pendingImages.isNotEmpty;
    if (!hasText && !hasImages) return;
    if (_isRunning) return;

    if (!_isModelInstalled) {
      setState(
        () => _errorMessage =
            'Download ${widget.modelInstaller.modelName} before using the AI coach.',
      );
      return;
    }

    final userMessage = ChatMessage(
      role: 'user',
      content: text,
      imageBytes: _pendingImages.map((i) => i.bytes).toList(),
      imageLabels: _pendingImages.map((i) => i.label).toList(),
    );

    final updatedMessages = [..._conversation.messages, userMessage];
    var conversation = _conversation.copyWith(messages: updatedMessages);

    if (conversation.title == 'Nuova chat' && text.isNotEmpty) {
      conversation = conversation.copyWith(
        title: text.length > 40 ? '${text.substring(0, 40)}...' : text,
      );
    }

    setState(() {
      _conversation = conversation;
      _textController.clear();
      _pendingImages = [];
      _isRunning = true;
      _errorMessage = null;
    });
    _scrollToBottom();

    await _saveAndRefresh(conversation);

    try {
      final response = await widget.service.generateChatResponse(
        history: widget.history,
        schedules: widget.schedules,
        bodyLogs: widget.bodyLogs,
        profile: _profile,
        memory: _memory,
        messages: updatedMessages,
        newImages: userMessage.hasImages
            ? userMessage.imageBytes
                  .map((bytes) => AiCoachImageInput(label: '', bytes: bytes))
                  .toList()
            : [],
      );

      final assistantMessage = ChatMessage(
        role: 'assistant',
        content: response,
      );
      final finalMessages = [...updatedMessages, assistantMessage];
      final finalConversation = conversation.copyWith(messages: finalMessages);

      if (!mounted) return;
      setState(() {
        _conversation = finalConversation;
        _isRunning = false;
      });
      _scrollToBottom();
      await _saveAndRefresh(finalConversation);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _errorMessage = 'Failed to get response. Please try again.';
      });
    }
  }

  Future<void> _handleSuggestionTap(String suggestion) async {
    _textController.text = suggestion;
    await _sendMessage();
  }

  Future<void> _reviewPlanAdjustments() async {
    if (_isAnalyzingPlan || _isRunning) return;
    if (!_isModelInstalled) {
      setState(
        () => _errorMessage =
            'Scarica il modello locale prima di analizzare la scheda.',
      );
      return;
    }
    setState(() {
      _isAnalyzingPlan = true;
      _errorMessage = null;
    });
    try {
      final report = await widget.service.suggestWorkoutAdjustments(
        history: widget.history,
        schedules: widget.schedules,
        bodyLogs: widget.bodyLogs,
        profile: _profile,
        memory: _memory,
      );
      final actions = widget.planActionService.validate(
        report,
        widget.schedules,
      );
      if (!mounted) return;
      if (actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nessuna modifica strutturata applicabile in sicurezza.',
            ),
          ),
        );
        return;
      }
      // Generation is complete: stop the app-bar spinner while the user reviews the diff.
      setState(() => _isAnalyzingPlan = false);
      final selected = await showModalBottomSheet<List<ValidatedPlanAction>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _PlanActionsReviewSheet(actions: actions),
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      final result = widget.planActionService.apply(widget.schedules, selected);
      if (result.applied > 0) {
        await AppDataStore.saveSchedules(widget.schedules);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.skipped == 0
                ? '${result.applied} modifiche applicate alla scheda.'
                : '${result.applied} applicate, ${result.skipped} saltate perché i dati erano cambiati.',
          ),
        ),
      );
    } on AiCoachInsufficientDataException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage =
            'Impossibile generare modifiche sicure alla scheda.',
      );
    } finally {
      if (mounted) setState(() => _isAnalyzingPlan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_conversation.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isModelInstalled)
            IconButton(
              key: const ValueKey('ai-plan-actions'),
              icon: _isAnalyzingPlan
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              tooltip: 'Proponi modifiche alla scheda',
              onPressed: _isAnalyzingPlan ? null : _reviewPlanAdjustments,
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
            onPressed: _editProfile,
          ),
          if (!_isModelInstalled && !_isCheckingModel)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download ${widget.modelInstaller.modelName}',
              onPressed: _downloadModel,
            ),
        ],
      ),
      drawer: _ChatHistoryDrawer(
        conversations: _allConversations,
        currentId: _conversation.id,
        onNewChat: _startNewConversation,
        onSwitch: _switchConversation,
        onDelete: _deleteConversation,
      ),
      body: Column(
        children: [
          if (_isCheckingModel)
            const LinearProgressIndicator()
          else if (_isDownloadingModel)
            LinearProgressIndicator(value: (_downloadProgress ?? 0) / 100)
          else if (_isModelInstalled && _allConversations.isEmpty)
            _ModelReadyBanner(theme: theme, colorScheme: colorScheme)
          else if (_errorMessage != null)
            _ErrorBanner(
              message: _errorMessage!,
              theme: theme,
              colorScheme: colorScheme,
              onDismiss: () => setState(() => _errorMessage = null),
            ),
          if (_isDownloadingModel && _downloadProgress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Downloading ${widget.modelInstaller.modelName}: $_downloadProgress%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: _conversation.messages.isEmpty
                ? _EmptyChatView(
                    theme: theme,
                    colorScheme: colorScheme,
                    onSuggestionTap: _handleSuggestionTap,
                    isModelReady: _isModelInstalled,
                    modelName: widget.modelInstaller.modelName,
                    onDownload: _downloadModel,
                    isDownloading: _isDownloadingModel,
                    downloadProgress: _downloadProgress,
                    isChecking: _isCheckingModel,
                    isInstalled: _isModelInstalled,
                  )
                : _ChatMessagesView(
                    messages: _conversation.messages,
                    isRunning: _isRunning,
                    scrollController: _scrollController,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
          ),
          if (_pendingImages.isNotEmpty)
            _PendingImagesBar(
              images: _pendingImages,
              onRemove: _removePendingImage,
              theme: theme,
              colorScheme: colorScheme,
            ),
          _ChatInputBar(
            controller: _textController,
            isRunning: _isRunning,
            hasText: _textController.text.trim().isNotEmpty,
            hasImages: _pendingImages.isNotEmpty,
            onSend: _sendMessage,
            onPickImages: _pickImages,
            theme: theme,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile() async {
    final ageController = TextEditingController(
      text: _profile.age?.toString() ?? '',
    );
    final heightController = TextEditingController(
      text: _profile.heightCm?.toString() ?? '',
    );
    final sexController = TextEditingController(text: _profile.sex);
    final levelController = TextEditingController(
      text: _profile.experienceLevel,
    );
    final goalController = TextEditingController(text: _profile.primaryGoal);
    final daysController = TextEditingController(
      text: _profile.daysAvailable?.toString() ?? '',
    );
    final minutesController = TextEditingController(
      text: _profile.sessionMinutes?.toString() ?? '',
    );
    final equipmentController = TextEditingController(text: _profile.equipment);
    final preferredController = TextEditingController(
      text: _profile.preferredExercises,
    );
    final avoidedController = TextEditingController(
      text: _profile.avoidedExercises,
    );
    final limitationsController = TextEditingController(
      text: _profile.limitations,
    );
    final notesController = TextEditingController(text: _profile.notes);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Coach Profile'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ageController,
                        decoration: const InputDecoration(labelText: 'Age'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: heightController,
                        decoration: const InputDecoration(
                          labelText: 'Height cm',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sexController,
                  decoration: const InputDecoration(labelText: 'Optional sex'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: levelController,
                  decoration: const InputDecoration(
                    labelText: 'Experience level',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: goalController,
                  decoration: const InputDecoration(labelText: 'Primary goal'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: daysController,
                        decoration: const InputDecoration(
                          labelText: 'Days/week',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: minutesController,
                        decoration: const InputDecoration(
                          labelText: 'Minutes/session',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: equipmentController,
                  decoration: const InputDecoration(
                    labelText: 'Available equipment',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: preferredController,
                  decoration: const InputDecoration(
                    labelText: 'Preferred exercises',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: avoidedController,
                  decoration: const InputDecoration(
                    labelText: 'Exercises to avoid',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: limitationsController,
                  decoration: const InputDecoration(
                    labelText: 'Known discomfort or limitations',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Coach notes'),
                  minLines: 1,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final profile = AiCoachUserProfile(
      age: int.tryParse(ageController.text.trim()),
      heightCm: double.tryParse(
        heightController.text.trim().replaceAll(',', '.'),
      ),
      sex: sexController.text.trim(),
      experienceLevel: levelController.text.trim(),
      primaryGoal: goalController.text.trim(),
      daysAvailable: int.tryParse(daysController.text.trim()),
      sessionMinutes: int.tryParse(minutesController.text.trim()),
      equipment: equipmentController.text.trim(),
      preferredExercises: preferredController.text.trim(),
      avoidedExercises: avoidedController.text.trim(),
      limitations: limitationsController.text.trim(),
      notes: notesController.text.trim(),
    );
    await _profileStore.save(profile);
    if (!mounted) return;
    setState(() => _profile = profile);
  }
}

class _ChatHistoryDrawer extends StatelessWidget {
  final List<ChatConversation> conversations;
  final String currentId;
  final VoidCallback onNewChat;
  final ValueChanged<ChatConversation> onSwitch;
  final ValueChanged<ChatConversation> onDelete;

  const _ChatHistoryDrawer({
    required this.conversations,
    required this.currentId,
    required this.onNewChat,
    required this.onSwitch,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.psychology_alt, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'AI Coach',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'New chat',
                    onPressed: () {
                      Navigator.pop(context);
                      onNewChat();
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: conversations.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No conversations yet. Start a new chat!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conv = conversations[index];
                        final isSelected = conv.id == currentId;
                        final preview = conv.lastMessagePreview;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Material(
                            color: isSelected
                                ? colorScheme.primaryContainer.withValues(
                                    alpha: 0.6,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.pop(context);
                                onSwitch(conv);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            conv.title,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (preview.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              preview,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _DeleteButton(
                                      onTap: () {
                                        Navigator.pop(context);
                                        onDelete(conv);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DeleteButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.delete_outline,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ModelReadyBanner extends StatelessWidget {
  const _ModelReadyBanner({required this.theme, required this.colorScheme});

  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Text(
            'AI model ready. Start a conversation!',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final VoidCallback onDismiss;

  const _ErrorBanner({
    required this.message,
    required this.theme,
    required this.colorScheme,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.errorContainer.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Function(String) onSuggestionTap;
  final bool isModelReady;
  final String modelName;
  final VoidCallback onDownload;
  final bool isDownloading;
  final int? downloadProgress;
  final bool isChecking;
  final bool isInstalled;

  const _EmptyChatView({
    required this.theme,
    required this.colorScheme,
    required this.onSuggestionTap,
    required this.isModelReady,
    required this.modelName,
    required this.onDownload,
    required this.isDownloading,
    required this.downloadProgress,
    required this.isChecking,
    required this.isInstalled,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 20),
        Icon(
          Icons.psychology_alt,
          size: 48,
          color: colorScheme.primary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'Il tuo coach AI personale',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Chiedi consigli sugli allenamenti, analisi dei progressi, suggerimenti e molto altro.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (!isInstalled && !isChecking) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Scarica il modello AI per iniziare',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$modelName (locale, dati privati)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: isDownloading ? null : onDownload,
                    icon: const Icon(Icons.download),
                    label: Text('Download $modelName'),
                  ),
                  if (isDownloading && downloadProgress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: (downloadProgress! / 100)),
                    const SizedBox(height: 4),
                    Text('$downloadProgress%'),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (isModelReady) ...[
          const SizedBox(height: 24),
          Text(
            'Cosa vuoi fare?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ..._suggestions.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ActionChip(
                avatar: Icon(s.icon, size: 18),
                label: Text(s.label),
                onPressed: () => onSuggestionTap(s.prompt),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

class _Suggestion {
  final IconData icon;
  final String label;
  final String prompt;
  const _Suggestion(this.icon, this.label, this.prompt);
}

const _suggestions = [
  _Suggestion(
    Icons.summarize,
    'Riassumi ultimo allenamento',
    'Fammi un riassunto del mio ultimo allenamento. Cosa è andato bene?',
  ),
  _Suggestion(
    Icons.date_range,
    'Report settimanale',
    'Genera un report della mia settimana di allenamento',
  ),
  _Suggestion(
    Icons.crisis_alert,
    'Analisi punti deboli',
    'Quali sono i miei punti deboli negli ultimi allenamenti?',
  ),
  _Suggestion(
    Icons.tune,
    'Suggerimenti',
    'Hai suggerimenti per migliorare i miei allenamenti?',
  ),
  _Suggestion(
    Icons.notes,
    'Riassumi note',
    'Cosa dicono le mie note di allenamento?',
  ),
  _Suggestion(
    Icons.compare,
    'Consiglio esercizi',
    'Che esercizi mi consigli per la prossima sessione?',
  ),
];

class _ChatMessagesView extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool isRunning;
  final ScrollController scrollController;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _ChatMessagesView({
    required this.messages,
    required this.isRunning,
    required this.scrollController,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: messages.length + (isRunning ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          return _ChatBubble(
            message: messages[index],
            theme: theme,
            colorScheme: colorScheme,
          );
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Thinking...'),
            ],
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _ChatBubble({
    required this.message,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final alignment = isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bgColor = isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final textColor = isUser ? colorScheme.onPrimary : colorScheme.onSurface;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (message.hasImages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                direction: Axis.horizontal,
                children: message.imageLabels.map((label) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (message.content.isNotEmpty)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: borderRadius,
              ),
              child: Text(
                message.content,
                style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingImagesBar extends StatelessWidget {
  final List<AiCoachImageInput> images;
  final ValueChanged<int> onRemove;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _PendingImagesBar({
    required this.images,
    required this.onRemove,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final image = images[index];
                  return Chip(
                    label: Text(image.label, style: theme.textTheme.bodySmall),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => onRemove(index),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isRunning;
  final bool hasText;
  final bool hasImages;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _ChatInputBar({
    required this.controller,
    required this.isRunning,
    required this.hasText,
    required this.hasImages,
    required this.onSend,
    required this.onPickImages,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'Upload photos',
            onPressed: isRunning ? null : onPickImages,
            color: colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Chiedi qualcosa...',
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              onSubmitted: (_) => onSend(),
              onChanged: (_) {},
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Send',
              onPressed: (hasText || hasImages) && !isRunning ? onSend : null,
              color: (hasText || hasImages) && !isRunning
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanActionsReviewSheet extends StatefulWidget {
  final List<ValidatedPlanAction> actions;

  const _PlanActionsReviewSheet({required this.actions});

  @override
  State<_PlanActionsReviewSheet> createState() =>
      _PlanActionsReviewSheetState();
}

class _PlanActionsReviewSheetState extends State<_PlanActionsReviewSheet> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.actions.length; i += 1) i,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modifiche proposte', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Il Coach propone, il validator controlla i valori e nulla cambia finché non confermi.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: widget.actions.length,
                itemBuilder: (context, index) {
                  final action = widget.actions[index];
                  return Card(
                    child: CheckboxListTile(
                      key: ValueKey('plan-action-$index'),
                      value: _selected.contains(index),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selected.add(index);
                          } else {
                            _selected.remove(index);
                          }
                        });
                      },
                      title: Text(action.title),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${action.scheduleTitle}: ${action.currentValue} → ${action.suggestedValue}',
                            ),
                            if (action.source.rationale.trim().isNotEmpty)
                              Text(action.source.rationale),
                            if (action.suggestionReason.trim().isNotEmpty)
                              Text('Motivo: ${action.suggestionReason}'),
                            Text('Confidenza: ${action.confidence}'),
                          ],
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('apply-plan-actions'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              _selected.map((i) => widget.actions[i]).toList(),
                            ),
                      child: Text('Applica ${_selected.length}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
