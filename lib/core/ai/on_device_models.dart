import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

const _desktopOnDevicePlatforms = {
  TargetPlatform.linux,
  TargetPlatform.macOS,
  TargetPlatform.windows,
};
const _mobileOnDevicePlatforms = {TargetPlatform.android, TargetPlatform.iOS};
const onDevicePlatforms = {
  ..._mobileOnDevicePlatforms,
  ..._desktopOnDevicePlatforms,
};

enum AiModelTier {
  low('Smaller download', Icons.science_rounded),
  recommended('Balanced', Icons.auto_awesome_rounded),
  high('Larger model', Icons.workspace_premium_rounded);

  final String label;
  final IconData icon;

  const AiModelTier(this.label, this.icon);
}

const downloadableAiModels = [
  DownloadableAiModel(
    id: 'gemma3_1b_it',
    name: 'Gemma 3 1B IT',
    sizeLabel: '586 MB',
    providerLabel: 'Gemma',
    tier: AiModelTier.low,
    resourceLabel: 'Small Google text model',
    mobileUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    accessUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    description:
        'Smallest supported local option. Uses compact prompts and needs benchmark results before it should be treated as a quality default.',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    needsHuggingFaceToken: true,
    supportedPlatforms: onDevicePlatforms,
  ),
  DownloadableAiModel(
    id: 'gemma3n_e2b_it',
    name: 'Gemma 3n E2B IT',
    sizeLabel: '3.1 GB',
    providerLabel: 'Gemma',
    tier: AiModelTier.recommended,
    resourceLabel: 'Advanced Google multimodal model',
    mobileUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm',
    accessUrl: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
    description:
        'Higher-capability Google model for newer devices with enough memory; candidate default once prompt benchmarks are green.',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    isAdvanced: true,
    needsHuggingFaceToken: true,
    supportedPlatforms: onDevicePlatforms,
  ),
  DownloadableAiModel(
    id: 'gemma3n_e4b_it',
    name: 'Gemma 3n E4B IT',
    sizeLabel: '6.5 GB',
    providerLabel: 'Gemma',
    tier: AiModelTier.high,
    resourceLabel: 'Large Google multimodal model',
    mobileUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4.litertlm',
    accessUrl: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview',
    description:
        'Large model option for powerful devices; benchmark before making it your daily default.',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    isAdvanced: true,
    needsHuggingFaceToken: true,
    supportedPlatforms: onDevicePlatforms,
  ),
  DownloadableAiModel(
    id: 'qwen3_0_6b',
    name: 'Qwen3 0.6B',
    sizeLabel: '586 MB',
    providerLabel: 'Qwen',
    tier: AiModelTier.low,
    resourceLabel: 'Balanced public text model',
    mobileUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    description:
        'Smaller public desktop option for short searches. Uses less storage; detailed requests may need the balanced model.',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    isAdvanced: false,
    supportedPlatforms: _desktopOnDevicePlatforms,
  ),
  DownloadableAiModel(
    id: 'deepseek_r1_qwen_1_5b',
    name: 'DeepSeek R1 Distill Qwen 1.5B',
    sizeLabel: '1.7 GB',
    providerLabel: 'DeepSeek',
    tier: AiModelTier.high,
    resourceLabel: 'Advanced reasoning model',
    mobileUrl:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv1280.task',
    desktopUrl:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
    description:
        'Reasoning-oriented candidate; benchmark before recommending because thinking output may add noise.',
    modelType: ModelType.deepSeek,
    fileType: ModelFileType.task,
    isAdvanced: true,
    supportedPlatforms: _desktopOnDevicePlatforms,
  ),
  DownloadableAiModel(
    id: 'qwen25_1_5b_instruct',
    name: 'Qwen 2.5 1.5B Instruct',
    sizeLabel: '1.6 GB',
    providerLabel: 'Qwen',
    tier: AiModelTier.recommended,
    resourceLabel: 'Advanced public text model',
    mobileUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    description:
        'Public instruction-following model for search filters and short explanations. No account, API key, or server required.',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    isAdvanced: false,
    supportedPlatforms: onDevicePlatforms,
  ),
];

class DownloadableAiModel {
  final String id;
  final String name;
  final String sizeLabel;
  final String providerLabel;
  final AiModelTier tier;
  final String resourceLabel;
  final String mobileUrl;
  final String? desktopUrl;
  final String? accessUrl;
  final String description;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool isAdvanced;
  final bool needsHuggingFaceToken;
  final Set<TargetPlatform> supportedPlatforms;

  const DownloadableAiModel({
    required this.id,
    required this.name,
    required this.sizeLabel,
    required this.providerLabel,
    required this.tier,
    required this.resourceLabel,
    required this.mobileUrl,
    this.desktopUrl,
    this.accessUrl,
    required this.description,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.isAdvanced = false,
    this.needsHuggingFaceToken = false,
    required this.supportedPlatforms,
  });

  // Conservative product guidance, not a promise of throughput or accuracy.
  int get minimumRamMb => switch (id) {
    'gemma3n_e4b_it' => 12000,
    'gemma3n_e2b_it' => 8000,
    'qwen25_1_5b_instruct' || 'deepseek_r1_qwen_1_5b' => 6000,
    _ => 3000,
  };

  int get downloadBytes => switch (id) {
    'gemma3n_e4b_it' => 6500000000,
    'gemma3n_e2b_it' => 3100000000,
    'qwen25_1_5b_instruct' => 1700000000,
    'deepseek_r1_qwen_1_5b' => 1800000000,
    _ => 650000000,
  };

  String get url {
    final desktop = desktopUrl;
    if (isDesktop && desktop != null) return desktop;
    return mobileUrl;
  }

  String get storageFileName {
    final path = Uri.parse(url).pathSegments.last;
    return path.isEmpty ? url.split('/').last : path;
  }

  String get accessPageUrl {
    final explicitUrl = accessUrl;
    if (explicitUrl != null) return explicitUrl;
    final uri = Uri.parse(url);
    if (uri.host != 'huggingface.co' || uri.pathSegments.length < 2) {
      return url;
    }
    return Uri.https(
      uri.host,
      '/${uri.pathSegments[0]}/${uri.pathSegments[1]}',
    ).toString();
  }

  bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  bool get supportsCurrentPlatform =>
      !kIsWeb && supportedPlatforms.contains(defaultTargetPlatform);

  bool get supportsSearchTools => false;

  String get platformNote {
    if (supportsCurrentPlatform) return description;
    return '$description This model is not available for this platform.';
  }
}
