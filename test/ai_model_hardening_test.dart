import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_model_manager.dart';
import 'package:gymapp/screens/ai_model_management.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Gemma artifact is immutable and integrity metadata is pinned', () {
    const installer = FlutterGemmaAiCoachModelInstaller();

    expect(installer.modelUrl, isNot(contains('/resolve/main/')));
    expect(
      installer.modelUrl,
      contains('/resolve/6b78abd019e61a1ca4cbe3b212d2c9ce8ff38a94/'),
    );
    expect(installer.expectedSizeBytes, 2588147712);
    expect(
      installer.expectedSha256,
      '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
    );
  });

  test('preflight blocks insufficient storage', () async {
    const installer = FlutterGemmaAiCoachModelInstaller(
      deviceProbe: _FakeDeviceProbe(
        AiModelDeviceProfile(
          platform: 'android',
          availableStorageBytes: 2 * 1024 * 1024 * 1024,
          totalMemoryBytes: 8 * 1024 * 1024 * 1024,
          lowRamDevice: false,
          abis: ['arm64-v8a'],
        ),
      ),
    );

    final report = await installer.preflight();

    expect(report.suitability, AiModelSuitability.unsupported);
    expect(report.canInstall, isFalse);
    expect(report.blockers.join(' '), contains('Spazio insufficiente'));
  });

  test('preflight blocks low-RAM and non ARM64 Android devices', () async {
    const installer = FlutterGemmaAiCoachModelInstaller(
      deviceProbe: _FakeDeviceProbe(
        AiModelDeviceProfile(
          platform: 'android',
          availableStorageBytes: 10 * 1024 * 1024 * 1024,
          totalMemoryBytes: 3 * 1024 * 1024 * 1024,
          lowRamDevice: true,
          abis: ['armeabi-v7a'],
        ),
      ),
    );

    final report = await installer.preflight();

    expect(report.canInstall, isFalse);
    expect(report.blockers.join(' '), contains('ARM64'));
    expect(report.blockers.join(' '), contains('low-RAM'));
    expect(report.blockers.join(' '), contains('RAM insufficiente'));
  });

  test('preflight warns instead of blocking a 4-6 GB RAM device', () async {
    const installer = FlutterGemmaAiCoachModelInstaller(
      deviceProbe: _FakeDeviceProbe(
        AiModelDeviceProfile(
          platform: 'android',
          availableStorageBytes: 10 * 1024 * 1024 * 1024,
          totalMemoryBytes: 5 * 1024 * 1024 * 1024,
          lowRamDevice: false,
          abis: ['arm64-v8a'],
        ),
      ),
    );

    final report = await installer.preflight();

    expect(report.suitability, AiModelSuitability.warning);
    expect(report.canInstall, isTrue);
    expect(report.needsConfirmation, isTrue);
    expect(report.warnings.join(' '), contains('6 GB'));
  });

  test(
    'lifecycle manifest and inference phase survive process-like reload',
    () async {
      const store = AiModelLifecycleStore();

      await store.setPhase('inference');
      expect(await const AiModelLifecycleStore().phase(), 'inference');

      await store.recordInstalled(version: 'v1', sha256: 'abc', sizeBytes: 123);

      expect(await store.phase(), 'idle');
      expect(
        await const AiModelLifecycleStore().manifestMatches(
          version: 'v1',
          sha256: 'abc',
          sizeBytes: 123,
        ),
        isTrue,
      );
      expect(
        await store.manifestMatches(
          version: 'v2',
          sha256: 'abc',
          sizeBytes: 123,
        ),
        isFalse,
      );
    },
  );

  testWidgets('management UI disables download for unsupported device', (
    tester,
  ) async {
    const installer = _FakeManagementInstaller(
      installed: false,
      preflightReport: AiModelPreflightReport(
        suitability: AiModelSuitability.unsupported,
        device: AiModelDeviceProfile(
          platform: 'android',
          manufacturer: 'Test',
          model: 'LowRam',
          availableStorageBytes: 2 * 1024 * 1024 * 1024,
          totalMemoryBytes: 3 * 1024 * 1024 * 1024,
          lowRamDevice: true,
          abis: ['arm64-v8a'],
        ),
        requiredStorageBytes: 4 * 1024 * 1024 * 1024,
        blockers: ['Spazio insufficiente per il modello.'],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: AiModelManagementScreen(installer: installer)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Non compatibile'), findsOneWidget);
    expect(find.textContaining('Spazio insufficiente'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ai-model-download')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('management UI exposes verify, reinstall and remove', (
    tester,
  ) async {
    const installer = _FakeManagementInstaller(
      installed: true,
      preflightReport: AiModelPreflightReport(
        suitability: AiModelSuitability.suitable,
        device: AiModelDeviceProfile(
          platform: 'android',
          availableStorageBytes: 10 * 1024 * 1024 * 1024,
          totalMemoryBytes: 8 * 1024 * 1024 * 1024,
          lowRamDevice: false,
          abis: ['arm64-v8a'],
        ),
        requiredStorageBytes: 4 * 1024 * 1024 * 1024,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: AiModelManagementScreen(installer: installer)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verificato'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-model-verify')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-model-reinstall')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-model-remove')), findsOneWidget);
  });
}

class _FakeDeviceProbe implements AiModelDeviceProbe {
  final AiModelDeviceProfile profile;
  const _FakeDeviceProbe(this.profile);

  @override
  Future<AiModelDeviceProfile> inspect() async => profile;
}

class _FakeManagementInstaller implements AiCoachManagedModelInstaller {
  final bool installed;
  final AiModelPreflightReport preflightReport;

  const _FakeManagementInstaller({
    required this.installed,
    required this.preflightReport,
  });

  @override
  String get modelName => 'Fake Gemma';

  @override
  String get modelFileName => 'fake.litertlm';

  @override
  String get modelUrl => 'https://example.com/fake.litertlm';

  @override
  String get modelSizeLabel => '~2.6 GB';

  @override
  String get modelVersion => 'fake-v1';

  @override
  String get expectedSha256 => '0123456789abcdef0123456789abcdef';

  @override
  int get expectedSizeBytes => 123;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isInstalled() async => installed;

  @override
  Future<void> install({void Function(int progress)? onProgress}) async {
    onProgress?.call(100);
  }

  @override
  Future<void> activateInstalledModel() async {}

  @override
  Future<AiModelPreflightReport> preflight() async => preflightReport;

  @override
  Future<AiModelHealthReport> verifyInstallation() async => installed
      ? const AiModelHealthReport(
          status: AiModelHealthStatus.healthy,
          message: 'Installazione verificata.',
          modelVersion: 'fake-v1',
          expectedSha256: '0123456789abcdef0123456789abcdef',
          runtimeLoadVerified: true,
        )
      : AiModelHealthReport.notInstalled();

  @override
  Future<AiModelRecoveryReport> recoverInterruptedState() async =>
      const AiModelRecoveryReport();

  @override
  Future<void> reinstall({void Function(int progress)? onProgress}) async {
    onProgress?.call(100);
  }

  @override
  Future<void> markInferenceStarted() async {}

  @override
  Future<void> markInferenceFinished() async {}

  @override
  Future<void> uninstall() async {}
}
