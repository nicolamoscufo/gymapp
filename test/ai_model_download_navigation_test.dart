import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_model_manager.dart';
import 'package:gymapp/screens/ai_model_management.dart';

void main() {
  testWidgets('model download progress survives route recreation', (tester) async {
    final installer = _FakeObservableInstaller();

    await tester.pumpWidget(
      MaterialApp(home: AiModelManagementScreen(installer: installer)),
    );
    await tester.pumpAndSettle();

    installer.beginDownload(37);
    await tester.pump();

    expect(find.text('37%'), findsOneWidget);
    expect(find.textContaining('continuerà in background'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    installer.updateProgress(61);
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(home: AiModelManagementScreen(installer: installer)),
    );
    await tester.pumpAndSettle();

    expect(find.text('61%'), findsOneWidget);
    expect(find.textContaining('continuerà in background'), findsOneWidget);

    installer.completeDownload();
    await tester.pumpAndSettle();

    expect(find.text('Verificato'), findsOneWidget);
    expect(find.text('61%'), findsNothing);
  });
}

class _FakeObservableInstaller implements AiCoachObservableModelInstaller {
  final Set<AiModelInstallStateListener> _listeners = {};
  bool _installed = false;
  bool _downloading = false;
  int? _progress;

  void beginDownload(int progress) {
    _downloading = true;
    _progress = progress;
    _notify();
  }

  void updateProgress(int progress) {
    _progress = progress;
    _notify();
  }

  void completeDownload() {
    _installed = true;
    _downloading = false;
    _progress = null;
    _notify();
  }

  void _notify() {
    for (final listener in List<AiModelInstallStateListener>.from(_listeners)) {
      listener();
    }
  }

  @override
  bool get isInstallInProgress => _downloading;

  @override
  int? get currentInstallProgress => _progress;

  @override
  void addInstallStateListener(AiModelInstallStateListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeInstallStateListener(AiModelInstallStateListener listener) {
    _listeners.remove(listener);
  }

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
  Future<bool> isInstalled() async => _installed;

  @override
  Future<void> install({void Function(int progress)? onProgress}) async {}

  @override
  Future<void> activateInstalledModel() async {}

  @override
  Future<AiModelPreflightReport> preflight() async => const AiModelPreflightReport(
    suitability: AiModelSuitability.suitable,
    device: AiModelDeviceProfile(
      platform: 'android',
      availableStorageBytes: 10 * 1024 * 1024 * 1024,
      totalMemoryBytes: 8 * 1024 * 1024 * 1024,
      lowRamDevice: false,
      abis: ['arm64-v8a'],
    ),
    requiredStorageBytes: 4 * 1024 * 1024 * 1024,
  );

  @override
  Future<AiModelHealthReport> verifyInstallation() async => _installed
      ? const AiModelHealthReport(
          status: AiModelHealthStatus.healthy,
          message: 'Installazione verificata.',
          modelVersion: 'fake-v1',
          expectedSha256: '0123456789abcdef0123456789abcdef',
          artifactDigestVerified: true,
          runtimeLoadVerified: true,
        )
      : AiModelHealthReport.notInstalled();

  @override
  Future<AiModelRecoveryReport> recoverInterruptedState() async =>
      const AiModelRecoveryReport();

  @override
  Future<void> uninstall() async {
    _installed = false;
  }

  @override
  Future<void> reinstall({void Function(int progress)? onProgress}) async {}

  @override
  Future<void> markInferenceStarted() async {}

  @override
  Future<void> markInferenceFinished() async {}
}
