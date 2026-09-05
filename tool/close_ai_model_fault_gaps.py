from pathlib import Path

# --- model manager -------------------------------------------------------------
path = Path('lib/ai_coach/ai_coach_model_manager.dart')
text = path.read_text()

marker = """abstract class AiModelDeviceProbe {
"""
insert = """typedef AiModelInstallStateListener = void Function();

/// Optional capability for installers whose download operation is scoped to
/// the application rather than a particular route/widget instance.
abstract class AiCoachObservableModelInstaller
    implements AiCoachManagedModelInstaller {
  bool get isInstallInProgress;
  int? get currentInstallProgress;

  void addInstallStateListener(AiModelInstallStateListener listener);
  void removeInstallStateListener(AiModelInstallStateListener listener);
}

abstract class AiModelDeviceProbe {
"""
assert text.count(marker) == 1
text = text.replace(marker, insert, 1)

text = text.replace(
    "class FlutterGemmaAiCoachModelInstaller\n    implements AiCoachManagedModelInstaller {",
    "class FlutterGemmaAiCoachModelInstaller\n    implements AiCoachObservableModelInstaller {",
    1,
)

ctor_marker = """  const FlutterGemmaAiCoachModelInstaller({
    this.deviceProbe = const PlatformAiModelDeviceProbe(),
    this.lifecycleStore = const AiModelLifecycleStore(),
  });

  static const int _gib = 1024 * 1024 * 1024;
"""
ctor_repl = """  const FlutterGemmaAiCoachModelInstaller({
    this.deviceProbe = const PlatformAiModelDeviceProbe(),
    this.lifecycleStore = const AiModelLifecycleStore(),
  });

  static Future<void>? _activeInstallFuture;
  static int? _activeInstallProgress;
  static final Set<AiModelInstallStateListener> _installStateListeners =
      <AiModelInstallStateListener>{};

  static const int _gib = 1024 * 1024 * 1024;
"""
assert text.count(ctor_marker) == 1
text = text.replace(ctor_marker, ctor_repl, 1)

storage_marker = """  int get requiredFreeStorageBytes => expectedSizeBytes + (768 * _mib);

  @protected
"""
storage_repl = """  int get requiredFreeStorageBytes => expectedSizeBytes + (768 * _mib);

  @override
  bool get isInstallInProgress => _activeInstallFuture != null;

  @override
  int? get currentInstallProgress => _activeInstallProgress;

  @override
  void addInstallStateListener(AiModelInstallStateListener listener) {
    _installStateListeners.add(listener);
  }

  @override
  void removeInstallStateListener(AiModelInstallStateListener listener) {
    _installStateListeners.remove(listener);
  }

  static void _notifyInstallState() {
    for (final listener in List<AiModelInstallStateListener>.from(
      _installStateListeners,
    )) {
      listener();
    }
  }

  @protected
"""
assert text.count(storage_marker) == 1
text = text.replace(storage_marker, storage_repl, 1)

init_old = """  @override
  Future<void> initialize() async {
    // flutter_gemma keeps installation metadata and temporary download files.
    // Cleanup is idempotent and is especially useful after process death.
    await performRuntimeCleanup();
  }
"""
init_new = """  @override
  Future<void> initialize() async {
    // Route recreation is not process death. Never sweep downloader state
    // while this Dart process still owns the application-scoped install.
    if (_activeInstallFuture != null) return;
    await performRuntimeCleanup();
  }
"""
assert text.count(init_old) == 1
text = text.replace(init_old, init_new, 1)

start = text.index("  @override\n  Future<void> install({void Function(int progress)? onProgress}) async {")
end = text.index("\n  @override\n  Future<void> activateInstalledModel() async {", start)
new_install = """  @override
  Future<void> install({void Function(int progress)? onProgress}) async {
    AiModelInstallStateListener? listener;
    if (onProgress != null) {
      listener = () {
        final progress = _activeInstallProgress;
        if (progress != null) onProgress(progress);
      };
      addInstallStateListener(listener);
      final progress = _activeInstallProgress;
      if (progress != null) onProgress(progress);
    }

    try {
      _activeInstallProgress ??= 0;
      _notifyInstallState();
      _activeInstallFuture ??= _runInstallAndReset();
      await _activeInstallFuture;
    } finally {
      if (listener != null) removeInstallStateListener(listener);
    }
  }

  Future<void> _runInstallAndReset() async {
    try {
      await _performFreshInstall();
    } finally {
      _activeInstallFuture = null;
      _activeInstallProgress = null;
      _notifyInstallState();
    }
  }

  Future<void> _performFreshInstall() async {
    final preflightReport = await preflight();
    if (!preflightReport.canInstall) {
      throw AiModelInstallException(
        preflightReport.userSummary,
        retryable: false,
      );
    }

    await lifecycleStore.setPhase('downloading');
    try {
      await performRuntimeCleanup();
      await installRuntimeModel(
        onProgress: (progress) {
          _activeInstallProgress = progress.clamp(0, 100);
          _notifyInstallState();
        },
      );

      if (!await isInstalled()) {
        throw const AiModelInstallException(
          'Il download è terminato ma il modello non risulta installato. Riprova la riparazione.',
        );
      }

      final artifact = await inspectInstalledArtifact();
      if (artifact.available &&
          !artifact.matches(
            expectedSizeBytes: expectedSizeBytes,
            expectedSha256: expectedSha256,
          )) {
        await removeRuntimeModel();
        await clearRuntimeInferenceIdentity();
        await performRuntimeCleanup();
        await lifecycleStore.clearManifest();
        throw const AiModelInstallException(
          'Il file scaricato non supera il controllo SHA-256/dimensione. L’artifact corrotto è stato rimosso: reinstalla il modello.',
          retryable: false,
        );
      }

      final runtimeHealthy = await performRuntimeLoadCheck();
      if (!runtimeHealthy) {
        throw const AiModelInstallException(
          'Il file è installato ma il runtime non riesce a caricarlo. Usa “Reinstalla modello”.',
        );
      }

      await lifecycleStore.recordInstalled(
        version: modelVersion,
        sha256: expectedSha256,
        sizeBytes: expectedSizeBytes,
        digestVerified: artifact.matches(
          expectedSizeBytes: expectedSizeBytes,
          expectedSha256: expectedSha256,
        ),
      );
    } on DownloadException catch (error) {
      await lifecycleStore.recordFailure(error);
      throw AiModelInstallException(
        error.error.toUserMessage(),
        retryable: error.error.isRetryable,
      );
    } catch (error) {
      await lifecycleStore.recordFailure(error);
      rethrow;
    }
  }
"""
text = text[:start] + new_install + text[end:]

act_start = text.index("  @override\n  Future<void> activateInstalledModel() async {")
act_end = text.index("\n  @override\n  Future<AiModelHealthReport> verifyInstallation() async {", act_start)
new_activate = """  @override
  Future<void> activateInstalledModel() async {
    final health = await verifyInstallation();
    final verifiedLegacy =
        health.status == AiModelHealthStatus.legacyUnverified &&
        health.artifactDigestVerified &&
        health.runtimeLoadVerified;
    if (health.status == AiModelHealthStatus.healthy || verifiedLegacy) return;

    throw StateError(
      '$modelName cannot be activated: ${health.message}',
    );
  }
"""
text = text[:act_start] + new_activate + text[act_end:]

recover_marker = """  @override
  Future<AiModelRecoveryReport> recoverInterruptedState() async {
    final phase = await lifecycleStore.phase();
"""
recover_repl = """  @override
  Future<AiModelRecoveryReport> recoverInterruptedState() async {
    // Navigation can create a new installer while the same native download is
    // still alive. That is not an interrupted download and must not trigger
    // cleanup/cancellation.
    if (_activeInstallFuture != null) {
      return const AiModelRecoveryReport();
    }

    final phase = await lifecycleStore.phase();
"""
assert text.count(recover_marker) == 1
text = text.replace(recover_marker, recover_repl, 1)

uninstall_marker = """  @override
  Future<void> uninstall() async {
    await lifecycleStore.setPhase('uninstalling');
"""
uninstall_repl = """  @override
  Future<void> uninstall() async {
    if (_activeInstallFuture != null) {
      throw const AiModelInstallException(
        'Attendi il completamento del download prima di rimuovere il modello.',
        retryable: false,
      );
    }
    await lifecycleStore.setPhase('uninstalling');
"""
assert text.count(uninstall_marker) == 1
text = text.replace(uninstall_marker, uninstall_repl, 1)

reinstall_marker = """  @override
  Future<void> reinstall({void Function(int progress)? onProgress}) async {
    if (await isInstalled()) {
"""
reinstall_repl = """  @override
  Future<void> reinstall({void Function(int progress)? onProgress}) async {
    if (_activeInstallFuture != null) {
      throw const AiModelInstallException(
        'Un download del modello è già in corso.',
        retryable: false,
      );
    }
    if (await isInstalled()) {
"""
assert text.count(reinstall_marker) == 1
text = text.replace(reinstall_marker, reinstall_repl, 1)
path.write_text(text)

# --- model management UI -------------------------------------------------------
path = Path('lib/screens/ai_model_management.dart')
text = path.read_text()
if not text.startswith("import 'dart:async';"):
    text = "import 'dart:async';\n\n" + text

state_marker = """  AiModelHealthReport _health = AiModelHealthReport.notInstalled();

  @override
  void initState() {
    super.initState();
    _refresh(runRecovery: true);
  }
"""
state_repl = """  AiModelHealthReport _health = AiModelHealthReport.notInstalled();

  AiCoachObservableModelInstaller? get _observableInstaller {
    final installer = widget.installer;
    return installer is AiCoachObservableModelInstaller ? installer : null;
  }

  @override
  void initState() {
    super.initState();
    _observableInstaller?.addInstallStateListener(_onInstallStateChanged);
    _refresh(runRecovery: true);
  }

  @override
  void dispose() {
    _observableInstaller?.removeInstallStateListener(_onInstallStateChanged);
    super.dispose();
  }

  void _onInstallStateChanged() {
    if (!mounted) return;
    final observable = _observableInstaller;
    if (observable == null) return;

    if (observable.isInstallInProgress) {
      setState(() {
        _busy = true;
        _progress = observable.currentInstallProgress ?? _progress ?? 0;
        if (!_installed) {
          _message =
              'Download di ${widget.installer.modelName} in corso. Puoi cambiare schermata: il download continuerà in background.';
        }
      });
      return;
    }

    if (_progress != null) {
      unawaited(_refresh());
    }
  }
"""
assert text.count(state_marker) == 1
text = text.replace(state_marker, state_repl, 1)

old_refresh_tail = """      final health = installed
          ? await widget.installer.verifyInstallation()
          : AiModelHealthReport.notInstalled();
      if (!mounted) return;
      setState(() {
        _preflight = preflight;
        _installed = installed;
        _health = health;
        _loading = false;
        if (recovery.userMessage != null) _message = recovery.userMessage;
      });
"""
new_refresh_tail = """      final health = installed
          ? await widget.installer.verifyInstallation()
          : AiModelHealthReport.notInstalled();
      final observable = _observableInstaller;
      final downloading = observable?.isInstallInProgress ?? false;
      final progress = observable?.currentInstallProgress;
      if (!mounted) return;
      setState(() {
        _preflight = preflight;
        _installed = installed;
        _health = health;
        _loading = false;
        _busy = downloading;
        _progress = downloading ? (progress ?? 0) : null;
        if (recovery.userMessage != null) {
          _message = recovery.userMessage;
        } else if (downloading) {
          _message =
              'Download di ${widget.installer.modelName} in corso. Puoi cambiare schermata: il download continuerà in background.';
        }
      });
"""
assert text.count(old_refresh_tail) == 1
text = text.replace(old_refresh_tail, new_refresh_tail, 1)
path.write_text(text)

# --- fault tests ---------------------------------------------------------------
path = Path('test/ai_model_fault_injection_test.dart')
text = path.read_text()
if not text.startswith("import 'dart:async';"):
    text = "import 'dart:async';\n\n" + text

insert_before = """  test('process-like restart clears stale inference phase without model mutation', () async {
"""
new_tests = """  test('live application-scoped download is not recovered as interrupted', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final first = _BlockingFaultInstaller(release: release, started: started);

    final install = first.install();
    await started.future;
    expect(first.isInstallInProgress, isTrue);

    final recreated = _FaultInstaller(installed: false);
    await recreated.initialize();
    final recovery = await recreated.recoverInterruptedState();

    expect(recovery.recovered, isFalse);
    expect(recreated.cleanupCalls, 0);
    expect(await recreated.lifecycleStore.phase(), 'downloading');

    release.complete();
    await install;
    expect(first.isInstallInProgress, isFalse);
    expect(await first.lifecycleStore.phase(), 'idle');
  });

  test('concurrent install callers join the same application-scoped download', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final first = _BlockingFaultInstaller(release: release, started: started);
    final second = _FaultInstaller(installed: false);
    final secondProgress = <int>[];

    final firstFuture = first.install();
    await started.future;
    final secondFuture = second.install(onProgress: secondProgress.add);

    expect(first.installCalls, 1);
    expect(second.installCalls, 0);
    expect(secondProgress, contains(0));

    release.complete();
    await Future.wait([firstFuture, secondFuture]);
    expect(first.installCalls, 1);
    expect(second.installCalls, 0);
    expect(secondProgress, contains(100));
  });

  test('activation fails closed on checksum mismatch even before runtime load', () async {
    final installer = _FaultInstaller(installed: true);
    installer.inspection = AiModelArtifactInspection(
      available: true,
      exists: true,
      sizeBytes: installer.expectedSizeBytes,
      sha256: 'deadbeef',
    );

    await expectLater(installer.activateInstalledModel(), throwsStateError);

    expect(installer.runtimeLoadCalls, 0);
  });

""" + insert_before
assert text.count(insert_before) == 1
text = text.replace(insert_before, new_tests, 1)

class_marker = """class _FaultDeviceProbe implements AiModelDeviceProbe {
"""
blocking_class = """class _BlockingFaultInstaller extends _FaultInstaller {
  final Completer<void> release;
  final Completer<void> started;

  _BlockingFaultInstaller({required this.release, required this.started})
    : super(installed: false);

  @override
  Future<void> installRuntimeModel({void Function(int progress)? onProgress}) async {
    installCalls++;
    onProgress?.call(0);
    if (!started.isCompleted) started.complete();
    await release.future;
    installed = true;
    onProgress?.call(100);
  }
}

class _FaultDeviceProbe implements AiModelDeviceProbe {
"""
assert text.count(class_marker) == 1
text = text.replace(class_marker, blocking_class, 1)
path.write_text(text)
