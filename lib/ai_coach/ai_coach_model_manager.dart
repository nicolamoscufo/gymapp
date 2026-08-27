import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiModelSuitability { suitable, warning, unsupported, unknown }

enum AiModelHealthStatus {
  notInstalled,
  healthy,
  legacyUnverified,
  versionMismatch,
  runtimeBroken,
}

enum AiModelInterruptedOperation { none, download, inference }

class AiModelDeviceProfile {
  final String platform;
  final String manufacturer;
  final String model;
  final int? androidSdk;
  final int? availableStorageBytes;
  final int? totalMemoryBytes;
  final bool? lowRamDevice;
  final List<String> abis;

  const AiModelDeviceProfile({
    this.platform = 'unknown',
    this.manufacturer = '',
    this.model = '',
    this.androidSdk,
    this.availableStorageBytes,
    this.totalMemoryBytes,
    this.lowRamDevice,
    this.abis = const [],
  });

  bool get isAndroid => platform == 'android';

  factory AiModelDeviceProfile.fromMap(Map<dynamic, dynamic> map) {
    return AiModelDeviceProfile(
      platform: map['platform']?.toString() ?? 'unknown',
      manufacturer: map['manufacturer']?.toString() ?? '',
      model: map['model']?.toString() ?? '',
      androidSdk: (map['androidSdk'] as num?)?.toInt(),
      availableStorageBytes: (map['availableStorageBytes'] as num?)?.toInt(),
      totalMemoryBytes: (map['totalMemoryBytes'] as num?)?.toInt(),
      lowRamDevice: map['lowRamDevice'] as bool?,
      abis: (map['abis'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}

class AiModelPreflightReport {
  final AiModelSuitability suitability;
  final AiModelDeviceProfile device;
  final int requiredStorageBytes;
  final List<String> blockers;
  final List<String> warnings;

  const AiModelPreflightReport({
    required this.suitability,
    required this.device,
    required this.requiredStorageBytes,
    this.blockers = const [],
    this.warnings = const [],
  });

  bool get canInstall => suitability != AiModelSuitability.unsupported;
  bool get needsConfirmation => warnings.isNotEmpty;

  factory AiModelPreflightReport.unknown() => const AiModelPreflightReport(
    suitability: AiModelSuitability.unknown,
    device: AiModelDeviceProfile(),
    requiredStorageBytes: 0,
  );

  String get userSummary {
    if (blockers.isNotEmpty) return blockers.join('\n');
    if (warnings.isNotEmpty) return warnings.join('\n');
    return 'Dispositivo compatibile con il modello locale.';
  }
}

class AiModelHealthReport {
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

  bool get isHealthy => status == AiModelHealthStatus.healthy;

  factory AiModelHealthReport.notInstalled() => const AiModelHealthReport(
    status: AiModelHealthStatus.notInstalled,
    message: 'Modello non installato.',
  );
}

class AiModelRecoveryReport {
  final AiModelInterruptedOperation interruptedOperation;
  final bool cleanupPerformed;
  final String? userMessage;

  const AiModelRecoveryReport({
    this.interruptedOperation = AiModelInterruptedOperation.none,
    this.cleanupPerformed = false,
    this.userMessage,
  });

  bool get recovered => interruptedOperation != AiModelInterruptedOperation.none;
}

class AiModelInstallException implements Exception {
  final String message;
  final bool retryable;

  const AiModelInstallException(this.message, {this.retryable = true});

  @override
  String toString() => message;
}

abstract class AiCoachModelInstaller {
  String get modelName;
  String get modelFileName;
  String get modelUrl;
  String get modelSizeLabel;

  String get modelVersion => 'unknown';
  String get expectedSha256 => '';
  int get expectedSizeBytes => 0;
  bool get canManageModel => false;

  Future<void> initialize();
  Future<bool> isInstalled();
  Future<void> install({void Function(int progress)? onProgress});
  Future<void> activateInstalledModel();

  Future<AiModelPreflightReport> preflight() async =>
      AiModelPreflightReport.unknown();

  Future<AiModelHealthReport> verifyInstallation() async {
    return await isInstalled()
        ? AiModelHealthReport(
            status: AiModelHealthStatus.healthy,
            message: 'Modello installato.',
            modelVersion: modelVersion,
            expectedSha256: expectedSha256,
            runtimeLoadVerified: false,
          )
        : AiModelHealthReport.notInstalled();
  }

  Future<AiModelRecoveryReport> recoverInterruptedState() async =>
      const AiModelRecoveryReport();

  Future<void> uninstall() async {
    throw UnsupportedError('Model uninstall is not supported by this installer.');
  }

  Future<void> reinstall({void Function(int progress)? onProgress}) async {
    await uninstall();
    await install(onProgress: onProgress);
  }

  Future<void> markInferenceStarted() async {}
  Future<void> markInferenceFinished() async {}
}

abstract class AiModelDeviceProbe {
  const AiModelDeviceProbe();
  Future<AiModelDeviceProfile> inspect();
}

class PlatformAiModelDeviceProbe implements AiModelDeviceProbe {
  const PlatformAiModelDeviceProbe();

  static const _channel = MethodChannel('gymapp/ai_model_device');

  @override
  Future<AiModelDeviceProfile> inspect() async {
    if (kIsWeb) {
      return const AiModelDeviceProfile(platform: 'web');
    }
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceProfile',
      );
      if (result == null) return const AiModelDeviceProfile();
      return AiModelDeviceProfile.fromMap(result);
    } on MissingPluginException {
      return AiModelDeviceProfile(platform: defaultTargetPlatform.name);
    } on PlatformException {
      return AiModelDeviceProfile(platform: defaultTargetPlatform.name);
    }
  }
}

class AiModelLifecycleStore {
  const AiModelLifecycleStore();

  static const _phaseKey = 'ai_model_lifecycle_phase_v1';
  static const _versionKey = 'ai_model_lifecycle_version_v1';
  static const _shaKey = 'ai_model_lifecycle_sha256_v1';
  static const _sizeKey = 'ai_model_lifecycle_size_v1';
  static const _installedAtKey = 'ai_model_lifecycle_installed_at_v1';
  static const _lastFailureKey = 'ai_model_lifecycle_last_failure_v1';

  Future<String> phase() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phaseKey) ?? 'idle';
  }

  Future<void> setPhase(String phase) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phaseKey, phase);
  }

  Future<void> recordInstalled({
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

  Future<void> recordFailure(Object error) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastFailureKey, error.toString());
    await prefs.setString(_phaseKey, 'failed');
  }

  Future<bool> manifestMatches({
    required String version,
    required String sha256,
    required int sizeBytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_versionKey) == version &&
        prefs.getString(_shaKey) == sha256 &&
        prefs.getInt(_sizeKey) == sizeBytes;
  }

  Future<bool> hasManifest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_versionKey) && prefs.containsKey(_shaKey);
  }

  Future<void> clearManifest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_versionKey);
    await prefs.remove(_shaKey);
    await prefs.remove(_sizeKey);
    await prefs.remove(_installedAtKey);
    await prefs.remove(_lastFailureKey);
    await prefs.setString(_phaseKey, 'idle');
  }
}

class FlutterGemmaAiCoachModelInstaller implements AiCoachModelInstaller {
  final AiModelDeviceProbe deviceProbe;
  final AiModelLifecycleStore lifecycleStore;

  const FlutterGemmaAiCoachModelInstaller({
    this.deviceProbe = const PlatformAiModelDeviceProbe(),
    this.lifecycleStore = const AiModelLifecycleStore(),
  });

  static const int _gib = 1024 * 1024 * 1024;
  static const int _mib = 1024 * 1024;

  @override
  String get modelName => 'Gemma 4 E2B';

  @override
  String get modelFileName => 'gemma-4-E2B-it.litertlm';

  // Pin the model to an immutable upstream revision. Integrity metadata below
  // corresponds to this exact artifact, not a mutable /main URL.
  @override
  String get modelUrl =>
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/6b78abd019e61a1ca4cbe3b212d2c9ce8ff38a94/gemma-4-E2B-it.litertlm';

  @override
  String get modelVersion => 'gemma4-e2b-litertlm-2026-08-27-r1';

  @override
  String get expectedSha256 =>
      '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c';

  @override
  int get expectedSizeBytes => 2588147712;

  @override
  String get modelSizeLabel => '~2.6 GB';

  @override
  bool get canManageModel => true;

  int get requiredFreeStorageBytes => expectedSizeBytes + (768 * _mib);

  @override
  Future<void> initialize() async {
    // flutter_gemma keeps installation metadata and temporary download files.
    // Cleanup is idempotent and is especially useful after process death.
    await FlutterGemma.performCleanup();
  }

  @override
  Future<bool> isInstalled() => FlutterGemma.isModelInstalled(modelFileName);

  @override
  Future<AiModelPreflightReport> preflight() async {
    final device = await deviceProbe.inspect();
    final blockers = <String>[];
    final warnings = <String>[];

    final free = device.availableStorageBytes;
    if (free != null && free < requiredFreeStorageBytes) {
      blockers.add(
        'Spazio insufficiente: servono almeno ${_formatGb(requiredFreeStorageBytes)} GB liberi per download, installazione e margine di sicurezza; disponibili ${_formatGb(free)} GB.',
      );
    } else if (free == null) {
      warnings.add(
        'Non riesco a misurare lo spazio libero su questo dispositivo. Verifica di avere almeno ${_formatGb(requiredFreeStorageBytes)} GB disponibili.',
      );
    }

    if (device.isAndroid) {
      if (device.abis.isNotEmpty && !device.abis.contains('arm64-v8a')) {
        blockers.add(
          'CPU non compatibile: questa build di Gemma 4 richiede un dispositivo Android ARM64.',
        );
      }
      if (device.lowRamDevice == true) {
        blockers.add(
          'Android classifica questo telefono come low-RAM: il modello locale da 2,6 GB non è adatto a questo dispositivo.',
        );
      }
    }

    final memory = device.totalMemoryBytes;
    if (memory != null && memory < 4 * _gib) {
      blockers.add(
        'RAM insufficiente (${_formatGb(memory)} GB): per Gemma 4 E2B servono almeno 4 GB di RAM fisica.',
      );
    } else if (memory != null && memory < 6 * _gib) {
      warnings.add(
        'Il dispositivo ha ${_formatGb(memory)} GB di RAM. Il modello può funzionare, ma Android potrebbe chiudere l’app sotto pressione di memoria; 6 GB o più sono consigliati.',
      );
    }

    final suitability = blockers.isNotEmpty
        ? AiModelSuitability.unsupported
        : warnings.isNotEmpty
        ? AiModelSuitability.warning
        : AiModelSuitability.suitable;

    return AiModelPreflightReport(
      suitability: suitability,
      device: device,
      requiredStorageBytes: requiredFreeStorageBytes,
      blockers: blockers,
      warnings: warnings,
    );
  }

  @override
  Future<void> install({void Function(int progress)? onProgress}) async {
    final preflightReport = await preflight();
    if (!preflightReport.canInstall) {
      throw AiModelInstallException(
        preflightReport.userSummary,
        retryable: false,
      );
    }

    await lifecycleStore.setPhase('downloading');
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

  @override
  Future<void> activateInstalledModel() async {
    if (!await isInstalled()) {
      throw StateError('$modelName is not installed.');
    }
    if (!await _runtimeLoadCheck()) {
      throw StateError('$modelName is installed but failed its runtime check.');
    }
  }

  @override
  Future<AiModelHealthReport> verifyInstallation() async {
    if (!await isInstalled()) return AiModelHealthReport.notInstalled();

    final runtimeHealthy = await _runtimeLoadCheck();
    if (!runtimeHealthy) {
      return AiModelHealthReport(
        status: AiModelHealthStatus.runtimeBroken,
        message:
            'Il modello è presente ma non supera il test di caricamento LiteRT-LM. Reinstallalo.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
        runtimeLoadVerified: false,
      );
    }

    final hasManifest = await lifecycleStore.hasManifest();
    if (!hasManifest) {
      return AiModelHealthReport(
        status: AiModelHealthStatus.legacyUnverified,
        message:
            'Installazione precedente rilevata e caricabile, ma senza manifest di versione/integrità. Reinstalla una volta per renderla verificata e riproducibile.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
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
        message:
            'La versione installata non corrisponde all’artifact Gemma 4 E2B fissato dall’app. È consigliata la reinstallazione.',
        modelVersion: modelVersion,
        expectedSha256: expectedSha256,
        runtimeLoadVerified: true,
      );
    }

    return AiModelHealthReport(
      status: AiModelHealthStatus.healthy,
      message:
          'Installazione verificata: versione/manifest corretti e test di caricamento LiteRT-LM superato.',
      modelVersion: modelVersion,
      expectedSha256: expectedSha256,
      runtimeLoadVerified: true,
    );
  }

  @override
  Future<AiModelRecoveryReport> recoverInterruptedState() async {
    final phase = await lifecycleStore.phase();
    if (phase == 'downloading') {
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
            userMessage:
                'Il download era stato interrotto, ma il modello risultava già completo: installazione recuperata e verificata.',
          );
        }
      }
      await lifecycleStore.setPhase('idle');
      return const AiModelRecoveryReport(
        interruptedOperation: AiModelInterruptedOperation.download,
        cleanupPerformed: true,
        userMessage:
            'Il download precedente è stato interrotto. I file temporanei sono stati ripuliti: puoi riprovare in sicurezza. Il server Hugging Face può richiedere di ricominciare il trasferimento.',
      );
    }

    if (phase == 'inference') {
      await lifecycleStore.setPhase('idle');
      return const AiModelRecoveryReport(
        interruptedOperation: AiModelInterruptedOperation.inference,
        cleanupPerformed: false,
        userMessage:
            'La risposta AI precedente è stata interrotta dalla chiusura dell’app. Il modello non è stato modificato: puoi inviare di nuovo la richiesta.',
      );
    }

    return const AiModelRecoveryReport();
  }

  @override
  Future<void> uninstall() async {
    await lifecycleStore.setPhase('uninstalling');
    try {
      await FlutterGemma.uninstallModel(modelFileName);
      await FlutterGemma.clearActiveInferenceIdentity();
      await FlutterGemma.performCleanup();
      await lifecycleStore.clearManifest();
    } catch (error) {
      await lifecycleStore.recordFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> reinstall({void Function(int progress)? onProgress}) async {
    if (await isInstalled()) {
      await uninstall();
    } else {
      await lifecycleStore.clearManifest();
      await FlutterGemma.performCleanup();
    }
    await install(onProgress: onProgress);
  }

  @override
  Future<void> markInferenceStarted() => lifecycleStore.setPhase('inference');

  @override
  Future<void> markInferenceFinished() async {
    if (await lifecycleStore.phase() == 'inference') {
      await lifecycleStore.setPhase('idle');
    }
  }

  Future<bool> _runtimeLoadCheck() async {
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

  static String _formatGb(int bytes) => (bytes / _gib).toStringAsFixed(1);
}
