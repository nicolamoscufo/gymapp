import 'package:flutter_gemma/flutter_gemma.dart';

abstract class AiCoachModelInstaller {
  String get modelName;
  String get modelFileName;
  String get modelUrl;
  String get modelSizeLabel;

  Future<void> initialize();
  Future<bool> isInstalled();
  Future<void> install({void Function(int progress)? onProgress});
  Future<void> activateInstalledModel();
}

class FlutterGemmaAiCoachModelInstaller implements AiCoachModelInstaller {
  const FlutterGemmaAiCoachModelInstaller();

  @override
  String get modelName => 'Gemma 4 E2B';

  @override
  String get modelFileName => 'gemma-4-E2B-it.litertlm';

  @override
  String get modelUrl =>
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  @override
  String get modelSizeLabel => '~2.6 GB';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isInstalled() => FlutterGemma.isModelInstalled(modelFileName);

  @override
  Future<void> install({void Function(int progress)? onProgress}) async {
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

  @override
  Future<void> activateInstalledModel() async {
    if (!await isInstalled()) {
      throw StateError('$modelName is not installed.');
    }
    // The modern flutter_gemma installer persists the active model so
    // getActiveModel() can restore it on subsequent runs.
  }
}
