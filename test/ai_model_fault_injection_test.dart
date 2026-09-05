import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_model_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('interrupted download is cleaned and reset for a safe retry', () async {
    final installer = _FaultInstaller(installed: false);
    await installer.lifecycleStore.setPhase('downloading');

    final report = await installer.recoverInterruptedState();

    expect(report.interruptedOperation, AiModelInterruptedOperation.download);
    expect(report.cleanupPerformed, isTrue);
    expect(installer.cleanupCalls, 1);
    expect(await installer.lifecycleStore.phase(), 'idle');
    expect(report.userMessage, contains('riprovare'));
  });

  test('completed artifact after process death is recovered and verified', () async {
    final installer = _FaultInstaller(installed: true);
    installer.inspection = AiModelArtifactInspection(
      available: true,
      exists: true,
      sizeBytes: installer.expectedSizeBytes,
      sha256: installer.expectedSha256,
    );
    await installer.lifecycleStore.setPhase('downloading');

    final report = await installer.recoverInterruptedState();

    expect(report.interruptedOperation, AiModelInterruptedOperation.download);
    expect(report.userMessage, contains('SHA-256'));
    expect(await installer.lifecycleStore.phase(), 'idle');
    expect(await installer.lifecycleStore.digestVerified(), isTrue);
    expect(
      await installer.lifecycleStore.manifestMatches(
        version: installer.modelVersion,
        sha256: installer.expectedSha256,
        sizeBytes: installer.expectedSizeBytes,
      ),
      isTrue,
    );
  });

  test('checksum mismatch is classified as integrity corruption', () async {
    final installer = _FaultInstaller(installed: true);
    installer.inspection = AiModelArtifactInspection(
      available: true,
      exists: true,
      sizeBytes: installer.expectedSizeBytes,
      sha256: 'deadbeef',
    );

    final health = await installer.verifyInstallation();

    expect(health.status, AiModelHealthStatus.integrityMismatch);
    expect(health.artifactDigestVerified, isFalse);
    expect(health.actualSha256, 'deadbeef');
    expect(installer.runtimeLoadCalls, 0);
  });

  test('size mismatch after interrupted download fails closed', () async {
    final installer = _FaultInstaller(installed: true);
    installer.inspection = AiModelArtifactInspection(
      available: true,
      exists: true,
      sizeBytes: installer.expectedSizeBytes - 4096,
      sha256: installer.expectedSha256,
    );
    await installer.lifecycleStore.setPhase('downloading');

    final report = await installer.recoverInterruptedState();

    expect(report.userMessage, contains('file non valido'));
    expect(await installer.lifecycleStore.phase(), 'failed');
    expect(installer.runtimeLoadCalls, 0);
  });

  test('runtime corruption is distinct from byte-integrity mismatch', () async {
    final installer = _FaultInstaller(installed: true, runtimeHealthy: false);
    installer.inspection = AiModelArtifactInspection(
      available: true,
      exists: true,
      sizeBytes: installer.expectedSizeBytes,
      sha256: installer.expectedSha256,
    );

    final health = await installer.verifyInstallation();

    expect(health.status, AiModelHealthStatus.runtimeBroken);
    expect(health.artifactDigestVerified, isTrue);
    expect(health.runtimeLoadVerified, isFalse);
  });

  test('unverified platform never silently claims byte-level integrity', () async {
    final installer = _FaultInstaller(installed: true);
    installer.inspection = const AiModelArtifactInspection.unavailable();
    await installer.lifecycleStore.recordInstalled(
      version: installer.modelVersion,
      sha256: installer.expectedSha256,
      sizeBytes: installer.expectedSizeBytes,
    );

    final health = await installer.verifyInstallation();

    expect(health.status, AiModelHealthStatus.integrityUnverified);
    expect(health.runtimeLoadVerified, isTrue);
    expect(health.artifactDigestVerified, isFalse);
  });

  test('low storage blocks install before the download runtime is touched', () async {
    final installer = _FaultInstaller(
      installed: false,
      device: const AiModelDeviceProfile(
        platform: 'android',
        availableStorageBytes: 2 * 1024 * 1024 * 1024,
        totalMemoryBytes: 8 * 1024 * 1024 * 1024,
        lowRamDevice: false,
        abis: ['arm64-v8a'],
      ),
    );

    await expectLater(installer.install(), throwsA(isA<AiModelInstallException>()));

    expect(installer.installCalls, 0);
    expect(await installer.lifecycleStore.phase(), 'idle');
  });

  test('injected download failure persists a recoverable failure phase', () async {
    final installer = _FaultInstaller(installed: false)
      ..installError = StateError('injected network interruption');

    await expectLater(installer.install(), throwsStateError);

    expect(installer.installCalls, 1);
    expect(await installer.lifecycleStore.phase(), 'failed');
  });

  test('process-like restart clears stale inference phase without model mutation', () async {
    final first = _FaultInstaller(installed: true);
    await first.lifecycleStore.setPhase('inference');

    final restarted = _FaultInstaller(installed: true);
    final report = await restarted.recoverInterruptedState();

    expect(report.interruptedOperation, AiModelInterruptedOperation.inference);
    expect(report.cleanupPerformed, isFalse);
    expect(await restarted.lifecycleStore.phase(), 'idle');
    expect(restarted.cleanupCalls, 0);
    expect(restarted.removeCalls, 0);
  });
}

class _FaultInstaller extends FlutterGemmaAiCoachModelInstaller {
  bool installed;
  bool runtimeHealthy;
  AiModelArtifactInspection inspection;
  Object? installError;
  int cleanupCalls = 0;
  int installCalls = 0;
  int runtimeLoadCalls = 0;
  int removeCalls = 0;
  int clearIdentityCalls = 0;

  _FaultInstaller({
    required this.installed,
    this.runtimeHealthy = true,
    AiModelDeviceProfile device = const AiModelDeviceProfile(
      platform: 'android',
      availableStorageBytes: 10 * 1024 * 1024 * 1024,
      totalMemoryBytes: 8 * 1024 * 1024 * 1024,
      lowRamDevice: false,
      abis: ['arm64-v8a'],
    ),
  }) : inspection = const AiModelArtifactInspection.unavailable(),
       super(deviceProbe: _FaultDeviceProbe(device));

  @override
  Future<void> performRuntimeCleanup() async {
    cleanupCalls++;
  }

  @override
  Future<bool> queryRuntimeInstallation() async => installed;

  @override
  Future<void> installRuntimeModel({void Function(int progress)? onProgress}) async {
    installCalls++;
    final error = installError;
    if (error != null) throw error;
    installed = true;
    onProgress?.call(100);
  }

  @override
  Future<AiModelArtifactInspection> inspectInstalledArtifact() async => inspection;

  @override
  Future<bool> performRuntimeLoadCheck() async {
    runtimeLoadCalls++;
    return runtimeHealthy;
  }

  @override
  Future<void> removeRuntimeModel() async {
    removeCalls++;
    installed = false;
  }

  @override
  Future<void> clearRuntimeInferenceIdentity() async {
    clearIdentityCalls++;
  }
}

class _FaultDeviceProbe implements AiModelDeviceProbe {
  final AiModelDeviceProfile device;
  const _FaultDeviceProbe(this.device);

  @override
  Future<AiModelDeviceProfile> inspect() async => device;
}
