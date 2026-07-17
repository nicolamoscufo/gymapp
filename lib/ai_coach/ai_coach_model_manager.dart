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
  String get modelSizeLabel => 'about 2.4 GB';

  @override
  String get modelUrl =>
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
      'resolve/b4f4f4df93418ddb4aa7da8bf33b584602a5b9f8/'
      'gemma-4-E2B-it.litertlm?download=true';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isInstalled() async {
    await initialize();
    try {
      return await FlutterGemma.isModelInstalled(modelFileName);
    } catch (_) {
      return FlutterGemma.hasActiveModel();
    }
  }

  @override
  Future<void> install({void Function(int progress)? onProgress}) async {
    await initialize();
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(modelUrl, foreground: true).withProgress((progress) {
      onProgress?.call(progress);
    }).install();
  }

  @override
  Future<void> activateInstalledModel() async {
    await initialize();
    if (!await isInstalled()) {
      throw StateError('$modelName is not installed.');
    }
  }
}
