from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one anchor, found {count}')
    return text.replace(old, new, 1)


# --- ai_coach_model_manager.dart -------------------------------------------------
path = Path('lib/ai_coach/ai_coach_model_manager.dart')
text = path.read_text()

text = replace_once(
    text,
    """enum AiModelHealthStatus {
  notInstalled,
  healthy,
  legacyUnverified,
  versionMismatch,
  runtimeBroken,
}
""",
    """enum AiModelHealthStatus {
  notInstalled,
  healthy,
  legacyUnverified,
  versionMismatch,
  integrityMismatch,
  integrityUnverified,
  runtimeBroken,
}
""",
    'health enum',
)

text = replace_once(
    text,
    """class AiModelHealthReport {
  final AiModelHealthStatus status;
  final String message;
  final String modelVersion;
  final String expectedSha256;
  final bool runtimeLoadVerified;

  const AiModelHealthReport({
    required this.status,
    required this.message,
    this.modelVersion = '',
    this.expectedSha256 = '',
    this.runtimeLoadVerified = false,
  });
""",
    """class AiModelHealthReport {
  final AiModelHealthStatus status;
  final String message;
  final String modelVersion;
  final String expectedSha256;
  final String actualSha256;
  final int? actualSizeBytes;
  final bool artifactDigestVerified;
  final bool runtimeLoadVerified;

  const AiModelHealthReport({
    required this.status,
    required this.message,
    this.modelVersion = '',
    this.expectedSha256 = '',
    this.actualSha256 = '',
    this.actualSizeBytes,
    this.artifactDigestVerified = false,
    this.runtimeLoadVerified = false,
  });
""",
    'health report fields',
)

text = replace_once(
    text,
    """class AiModelRecoveryReport {
""",
    """class AiModelArtifactInspection {
  final bool available;
  final bool exists;
  final int? sizeBytes;
  final String sha256;
  final String? error;

  const AiModelArtifactInspection({
    required this.available,
    this.exists = false,
    this.sizeBytes,
    this.sha256 = '',
    this.error,
  });

  const AiModelArtifactInspection.unavailable([String? reason])
    : available = false,
      exists = false,
      sizeBytes = null,
      sha256 = '',
      error = reason;

  factory AiModelArtifactInspection.fromMap(Map<dynamic, dynamic> map) {
    return AiModelArtifactInspection(
      available: true,
      exists: map['exists'] == true,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      sha256: map['sha256']?.toString().toLowerCase() ?? '',
      error: map['error']?.toString(),
    );
  }

  bool matches({required int expectedSizeBytes, required String expectedSha256}) {
    return available &&
        exists &&
        sizeBytes == expectedSizeBytes &&
        sha256 == expectedSha256.toLowerCase();
  }
}

class AiModelRecoveryReport {
""",
    'artifact inspection class',
)

text = replace_once(
    text,
    """  static const _installedAtKey = 'ai_model_lifecycle_installed_at_v1';
  static const _lastFailureKey = 'ai_model_lifecycle_last_failure_v1';
""",
    """  static const _installedAtKey = 'ai_model_lifecycle_installed_at_v1';
  static const _lastFailureKey = 'ai_model_lifecycle_last_failure_v1';
  static const _digestVerifiedKey = 'ai_model_lifecycle_digest_verified_v1';
""",
    'digest key',
)

text = replace_once(
    text,
    """  Future<void> recordInstalled({
    required String version,
    required String sha256,
    required int sizeBytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versionKey, version);
    await prefs.setString(_shaKey, sha256);
    await prefs.setInt(_sizeKey, sizeBytes);
    await prefs.setString(_installedAtKey, DateTime.now().toIso8601String());
    await prefs.remove(_lastFailureKey);
    await prefs.setString(_phaseKey, 'idle');
  }
""",
    """  Future<void> recordInstalled({
    required String version,
    required String sha256,
    required int sizeBytes,
    bool digestVerified = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versionKey, version);
    await prefs.setString(_shaKey, sha256);
    await prefs.setInt(_sizeKey, sizeBytes);
    await prefs.setBool(_digestVerifiedKey, digestVerified);
    await prefs.setString(_installedAtKey, DateTime.now().toIso8601String());
    await prefs.remove(_lastFailureKey);
    await prefs.setString(_phaseKey, 'idle');
  }

  Future<bool> digestVerified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_digestVerifiedKey) ?? false;
  }

  Future<void> setDigestVerified(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_digestVerifiedKey, value);
  }
""",
    'record installed digest',
)

text = replace_once(
    text,
    """    await prefs.remove(_lastFailureKey);
    await prefs.setString(_phaseKey, 'idle');
  }
}

class FlutterGemmaAiCoachModelInstaller
""",
    """    await prefs.remove(_lastFailureKey);
    await prefs.remove(_digestVerifiedKey);
    await prefs.setString(_phaseKey, 'idle');
  }
}

class FlutterGemmaAiCoachModelInstaller
""",
    'clear digest',
)

text = replace_once(
    text,
    """  static const int _gib = 1024 * 1024 * 1024;
  static const int _mib = 1024 * 1024;
""",
    """  static const int _gib = 1024 * 1024 * 1024;
  static const int _mib = 1024 * 1024;
  static const _deviceChannel = MethodChannel('gymapp/ai_model_device');
""",
    'installer channel',
)

anchor = """  int get requiredFreeStorageBytes => expectedSizeBytes + (768 * _mib);

  @override
  Future<void> initialize() async {
    // flutter_gemma keeps installation metadata and temporary download files.
    // Cleanup is idempotent and is especially useful after process death.
    await FlutterGemma.performCleanup();
  }

  @override
  Future<bool> isInstalled() => FlutterGemma.isModelInstalled(modelFileName);
"""
replacement = """  int get requiredFreeStorageBytes => expectedSizeBytes + (768 * _mib);

  @protected
  Future<void> performRuntimeCleanup() => FlutterGemma.performCleanup();

  @protected
  Future<bool> queryRuntimeInstallation() =>
      FlutterGemma.isModelInstalled(modelFileName);

  @protected
  Future<void> installRuntimeModel({void Function(int progress)? onProgress}) async {
    final installer = FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(modelUrl, foreground: true);

    if (onProgress != null) {
      await installer.withProgress(onProgress).install();
    } else {
      await installer.install();
    }
  }

  @protected
  Future<AiModelArtifactInspection> inspectInstalledArtifact() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const AiModelArtifactInspection.unavailable(
        'Byte-level SHA-256 inspection is currently available on Android only.',
      );
    }
    try {
      final path = await FlutterGemma.getModelPath(modelFileName);
      final result = await _deviceChannel.invokeMethod<Map<dynamic, dynamic>>(
        'inspectModelArtifact',
        {'path': path},
      );
      if (result == null) {
        return const AiModelArtifactInspection.unavailable(
          'Native artifact inspection returned no result.',
        );
      }
      return AiModelArtifactInspection.fromMap(result);
    } on MissingPluginException catch (error) {
      return AiModelArtifactInspection.unavailable(error.toString());
    } on PlatformException catch (error) {
      return AiModelArtifactInspection.unavailable(error.message);
    }
  }

  @protected
  Future<bool> performRuntimeLoadCheck() async {
    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        supportImage: false,
      );
      await model.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  @protected
  Future<void> removeRuntimeModel() => FlutterGemma.uninstallModel(modelFileName);

  @protected
  Future<void> clearRuntimeInferenceIdentity() =>
      FlutterGemma.clearActiveInferenceIdentity();

  @override
  Future<void> initialize() async {
    // flutter_gemma keeps installation metadata and temporary download files.
    // Cleanup is idempotent and is especially useful after process death.
    await performRuntimeCleanup();
  }

  @override
  Future<bool> isInstalled() => queryRuntimeInstallation();
"""
text = replace_once(text, anchor, replacement, 'runtime hooks')

old_install = """    await lifecycleStore.setPhase('downloading');
    try {
      await FlutterGemma.performCleanup();
      final installer = FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromNetwork(modelUrl, foreground: true);

      if (onProgress != null) {
        await installer.withProgress(onProgress).install();
      } else {
        await installer.install();
      }

      if (!await isInstalled()) {
        throw const AiModelInstallException(
          'Il download è terminato ma il modello non risulta installato. Riprova la riparazione.',
        );
      }

      final runtimeHealthy = await _runtimeLoadCheck();
      if (!runtimeHealthy) {
        throw const AiModelInstallException(
          'Il file è installato ma il runtime non riesce a caricarlo. Usa “Reinstalla modello”.',
        );
      }

      await lifecycleStore.recordInstalled(
        version: modelVersion,
        sha256: expectedSha256,
        sizeBytes: expectedSizeBytes,
      );
"""
new_install = """    await lifecycleStore.setPhase('downloading');
    try {
      await performRuntimeCleanup();
      await installRuntimeModel(onProgress: onProgress);

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
        throw const AiModelInstallException(
          'Il file scaricato non supera il controllo SHA-256/dimensione. L’installazione è considerata corrotta e va reinstallata.',
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
"""
text = replace_once(text, old_install, new_install, 'install path')

text = text.replace('if (!await _runtimeLoadCheck()) {', 'if (!await performRuntimeLoadCheck()) {')

start = text.index('  @override\n  Future<AiModelHealthReport> verifyInstallation() async {')
end = text.index('\n  @override\n  Future<AiModelRecoveryReport> recoverInterruptedState() async {', start)
new_verify = """  @override
  Future<AiModelHealthReport> verifyInstallation() async {
    if (!await isInstalled()) return AiModelHealthReport.notInstalled();

    final artifact = await inspectInstalledArtifact();
    final artifactMatches = artifact.matches(
      expectedSizeBytes: expectedSizeBytes,
      expectedSha256: expectedSha256,
    );
    if (artifact.available && !artifactMatches) {
      return AiModelHealthReport(
        status: AiModelHealthStatus.integrityMismatch,
        message: 'Il file installato non corrisponde al SHA-256 o alla dimensione attesi. Non usarlo: reinstalla il modello.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
        actualSha256: artifact.sha256,
        actualSizeBytes: artifact.sizeBytes,
        artifactDigestVerified: false,
        runtimeLoadVerified: false,
      );
    }

    final runtimeHealthy = await performRuntimeLoadCheck();
    if (!runtimeHealthy) {
      return AiModelHealthReport(
        status: AiModelHealthStatus.runtimeBroken,
        message: 'Il modello è presente ma non supera il test di caricamento LiteRT-LM. Reinstallalo.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
        actualSha256: artifact.sha256,
        actualSizeBytes: artifact.sizeBytes,
        artifactDigestVerified: artifactMatches,
        runtimeLoadVerified: false,
      );
    }

    final hasManifest = await lifecycleStore.hasManifest();
    if (!hasManifest) {
      return AiModelHealthReport(
        status: AiModelHealthStatus.legacyUnverified,
        message: 'Installazione precedente rilevata e caricabile, ma senza manifest di versione. Verificala/reinstallala una volta per renderla riproducibile.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
        actualSha256: artifact.sha256,
        actualSizeBytes: artifact.sizeBytes,
        artifactDigestVerified: artifactMatches,
        runtimeLoadVerified: true,
      );
    }

    final manifestMatches = await lifecycleStore.manifestMatches(
      version: modelVersion,
      sha256: expectedSha256,
      sizeBytes: expectedSizeBytes,
    );
    if (!manifestMatches) {
      return AiModelHealthReport(
        status: AiModelHealthStatus.versionMismatch,
        message: 'La versione installata non corrisponde all’artifact Gemma 4 E2B fissato dall’app. È consigliata la reinstallazione.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
        actualSha256: artifact.sha256,
        actualSizeBytes: artifact.sizeBytes,
        artifactDigestVerified: artifactMatches,
        runtimeLoadVerified: true,
      );
    }

    if (artifactMatches) {
      await lifecycleStore.setDigestVerified(true);
    }
    final digestVerified = artifactMatches || await lifecycleStore.digestVerified();
    if (!digestVerified) {
      return AiModelHealthReport(
        status: AiModelHealthStatus.integrityUnverified,
        message: 'Versione e runtime sono coerenti, ma questo dispositivo non ha ancora una verifica SHA-256 persistita per i byte installati.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
        actualSha256: artifact.sha256,
        actualSizeBytes: artifact.sizeBytes,
        artifactDigestVerified: false,
        runtimeLoadVerified: true,
      );
    }

    return AiModelHealthReport(
      status: AiModelHealthStatus.healthy,
      message: 'Installazione verificata: SHA-256/dimensione, manifest e caricamento LiteRT-LM sono coerenti.',
      modelVersion: modelVersion,
      expectedSha256: expectedSha256,
      actualSha256: artifact.sha256,
      actualSizeBytes: artifact.sizeBytes,
      artifactDigestVerified: true,
      runtimeLoadVerified: true,
    );
  }
"""
text = text[:start] + new_verify + text[end:]

old_recovery = """    if (phase == 'downloading') {
      await FlutterGemma.performCleanup();
      if (await isInstalled()) {
        final runtimeHealthy = await _runtimeLoadCheck();
        if (runtimeHealthy) {
          await lifecycleStore.recordInstalled(
            version: modelVersion,
            sha256: expectedSha256,
            sizeBytes: expectedSizeBytes,
          );
          return const AiModelRecoveryReport(
            interruptedOperation: AiModelInterruptedOperation.download,
            cleanupPerformed: true,
            userMessage: 'Il download era stato interrotto, ma il modello risultava già completo: installazione recuperata e verificata.',
          );
        }
      }
      await lifecycleStore.setPhase('idle');
      return const AiModelRecoveryReport(
        interruptedOperation: AiModelInterruptedOperation.download,
        cleanupPerformed: true,
        userMessage: 'Il download precedente è stato interrotto. I file temporanei sono stati ripuliti: puoi riprovare in sicurezza. Il server Hugging Face può richiedere di ricominciare il trasferimento.',
      );
    }
"""
new_recovery = """    if (phase == 'downloading') {
      await performRuntimeCleanup();
      if (await isInstalled()) {
        final artifact = await inspectInstalledArtifact();
        final artifactMatches = artifact.matches(
          expectedSizeBytes: expectedSizeBytes,
          expectedSha256: expectedSha256,
        );
        if (artifact.available && !artifactMatches) {
          await lifecycleStore.recordFailure(
            'Interrupted download left an integrity-mismatched artifact.',
          );
          return const AiModelRecoveryReport(
            interruptedOperation: AiModelInterruptedOperation.download,
            cleanupPerformed: true,
            userMessage: 'Il download interrotto ha lasciato un file non valido. Reinstalla il modello prima di usare il Coach.',
          );
        }

        final runtimeHealthy = await performRuntimeLoadCheck();
        if (runtimeHealthy) {
          await lifecycleStore.recordInstalled(
            version: modelVersion,
            sha256: expectedSha256,
            sizeBytes: expectedSizeBytes,
            digestVerified: artifactMatches,
          );
          return AiModelRecoveryReport(
            interruptedOperation: AiModelInterruptedOperation.download,
            cleanupPerformed: true,
            userMessage: artifactMatches
                ? 'Il download era stato interrotto, ma il file è completo: SHA-256, dimensione e runtime sono stati verificati.'
                : 'Il download era stato interrotto, ma il runtime riesce a caricare il modello. La verifica byte-level non è disponibile su questa piattaforma.',
          );
        }
      }
      await lifecycleStore.setPhase('idle');
      return const AiModelRecoveryReport(
        interruptedOperation: AiModelInterruptedOperation.download,
        cleanupPerformed: true,
        userMessage: 'Il download precedente è stato interrotto. I file temporanei sono stati ripuliti: puoi riprovare in sicurezza. Il server Hugging Face può richiedere di ricominciare il trasferimento.',
      );
    }
"""
text = replace_once(text, old_recovery, new_recovery, 'recovery path')

text = replace_once(
    text,
    """      await FlutterGemma.uninstallModel(modelFileName);
      await FlutterGemma.clearActiveInferenceIdentity();
      await FlutterGemma.performCleanup();
""",
    """      await removeRuntimeModel();
      await clearRuntimeInferenceIdentity();
      await performRuntimeCleanup();
""",
    'uninstall runtime',
)
text = replace_once(
    text,
    """      await lifecycleStore.clearManifest();
      await FlutterGemma.performCleanup();
""",
    """      await lifecycleStore.clearManifest();
      await performRuntimeCleanup();
""",
    'reinstall cleanup',
)

old_runtime = """  Future<bool> _runtimeLoadCheck() async {
    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        supportImage: false,
      );
      await model.close();
      return true;
    } catch (_) {
      return false;
    }
  }

"""
if old_runtime in text:
    text = text.replace(old_runtime, '', 1)

path.write_text(text)


# --- local_llm_engine.dart --------------------------------------------------------
path = Path('lib/ai_coach/local_llm_engine.dart')
text = path.read_text()
text = replace_once(
    text,
    "import 'ai_coach_model_manager.dart';\n",
    "import 'ai_coach_model_manager.dart';\nimport 'ai_model_execution_coordinator.dart';\n",
    'coordinator import',
)
text = replace_once(
    text,
    """  static InferenceModel? _model;
  static bool _isReady = false;
  static bool _modelSupportsImages = false;

  @override
  Future<void> initialize() async {
    await _ensureModel(supportImage: false);
  }
""",
    """  static InferenceModel? _model;
  static bool _isReady = false;
  static bool _modelSupportsImages = false;
  static final AiModelExecutionCoordinator _execution =
      AiModelExecutionCoordinator();

  @override
  Future<void> initialize() =>
      _execution.ensureReady(() => _ensureModel(supportImage: false));
""",
    'engine coordinator init',
)
text = replace_once(
    text,
    """  @override
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _modelSupportsImages = false;
    _isReady = false;
  }
""",
    """  @override
  Future<void> dispose() => _execution.dispose(_disposeUnlocked);

  Future<void> _disposeUnlocked() async {
    await _model?.close();
    _model = null;
    _modelSupportsImages = false;
    _isReady = false;
  }
""",
    'engine dispose',
)

for method, args, call_args in [
    (
        'generateStructuredJsonWithImages',
        """    String prompt,
    Map<String, dynamic> schema,
    List<AiCoachImageInput> images,
""",
        'prompt, schema, images',
    ),
    (
        'generateChatText',
        """    required String systemPrompt,
    required List<ChatMessage> messages,
    List<AiCoachImageInput> newImages = const [],
""",
        'systemPrompt: systemPrompt, messages: messages, newImages: newImages',
    ),
    (
        'generateText',
        """    String prompt,
""",
        'prompt',
    ),
]:
    if method == 'generateChatText':
        old = f"""  @override
  Future<String> {method}({{
{args}  }}) async {{
"""
        new = f"""  @override
  Future<String> {method}({{
{args}  }}) {{
    return _execution.runExclusive(() async {{
      await _execution.ensureReady(() => _ensureModel(supportImage: false));
      return _{method}Unlocked({call_args});
    }});
  }}

  Future<String> _{method}Unlocked({{
{args}  }}) async {{
"""
    else:
        old = f"""  @override
  Future<String> {method}(
{args}  ) async {{
"""
        new = f"""  @override
  Future<String> {method}(
{args}  ) {{
    return _execution.runExclusive(() async {{
      await _execution.ensureReady(() => _ensureModel(supportImage: false));
      return _{method}Unlocked({call_args});
    }});
  }}

  Future<String> _{method}Unlocked(
{args}  ) async {{
"""
    text = replace_once(text, old, new, f'wrap {method}')
path.write_text(text)


# --- Android native artifact hashing ---------------------------------------------
path = Path('android/app/src/main/kotlin/com/example/gymapp/MainActivity.kt')
text = path.read_text()
text = replace_once(
    text,
    """import io.flutter.plugin.common.MethodChannel
""",
    """import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
""",
    'kotlin imports',
)
text = replace_once(
    text,
    '                "getDeviceProfile" -> result.success(buildAiModelDeviceProfile())\n',
    """                "getDeviceProfile" -> result.success(buildAiModelDeviceProfile())
                "inspectModelArtifact" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Missing model artifact path", null)
                    } else {
                        inspectModelArtifact(path, result)
                    }
                }
""",
    'kotlin method handler',
)
text = replace_once(
    text,
    """    private fun buildAiModelDeviceProfile(): Map<String, Any?> {
""",
    """    private fun inspectModelArtifact(path: String, result: MethodChannel.Result) {
        Thread {
            try {
                val file = File(path)
                if (!file.exists() || !file.isFile) {
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "exists" to false,
                                "sizeBytes" to null,
                                "sha256" to "",
                            ),
                        )
                    }
                    return@Thread
                }

                val digest = MessageDigest.getInstance("SHA-256")
                FileInputStream(file).buffered(1024 * 1024).use { input ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        digest.update(buffer, 0, read)
                    }
                }
                val sha256 = digest.digest().joinToString("") { "%02x".format(it) }
                runOnUiThread {
                    result.success(
                        mapOf(
                            "exists" to true,
                            "sizeBytes" to file.length(),
                            "sha256" to sha256,
                        ),
                    )
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.success(
                        mapOf(
                            "exists" to false,
                            "sizeBytes" to null,
                            "sha256" to "",
                            "error" to (error.message ?: error.javaClass.simpleName),
                        ),
                    )
                }
            }
        }.start()
    }

    private fun buildAiModelDeviceProfile(): Map<String, Any?> {
""",
    'kotlin inspector',
)
path.write_text(text)
