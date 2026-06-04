import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

const externalLocalAiProvider = 'External local server';
const externalCloudAiProvider = 'External cloud API';
const fallbackRulesProvider = 'Fallback rules only';
const localAiModeOnDevice = 'Automatic on-device';
const localAiModeExternalServer = externalLocalAiProvider;
const localAiModeExternalCloud = externalCloudAiProvider;
const localAiModeManual = 'Manual copy/paste';
const localAiModeRulesOnly = fallbackRulesProvider;
const localAiBackendAuto = 'auto';
const localAiBackendCpu = 'cpu';
const localAiBackendGpu = 'gpu';
const localAiBackendNpu = 'npu';
const defaultLocalAiEndpoint = 'http://127.0.0.1:11434';
const defaultLocalAiModel = 'qwen3:4b-instruct';
const defaultCloudAiProvider = 'Google Gemini';
const defaultCloudAiEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
const defaultCloudAiModel = 'gemini-3.1-flash-lite';
const defaultOnDeviceContextWindowTokens = 4096;
const defaultLocalServerContextWindowTokens = 16384;
const defaultCloudContextWindowTokens = 131072;
const defaultManualContextWindowTokens = 1048576;
const minimumAiContextWindowTokens = 2048;
const maximumAiContextWindowTokens = 1048576;

class LocalAiSettingsKeys {
  static const immersiveReader = 'settings.immersiveReader';
  static const downloadOnWifiOnly = 'settings.downloadOnWifiOnly';
  static const allowExplicitContent = 'settings.allowExplicitContent';
  static const enableMotionEffects = 'settings.enableMotionEffects';
  static const useLocalAi = 'settings.useLocalAi';
  static const useAiForSearch = 'settings.useAiForSearch';
  static const localAiMode = 'settings.localAiMode';
  static const localBackend = 'settings.localBackend';
  static const localAiProvider = 'settings.localAiProvider';
  static const selectedModelId = 'settings.selectedModelId';
  static const selectedModelName = 'settings.selectedModelName';
  static const downloadedModelId = 'settings.downloadedModelId';
  static const downloadedModelName = 'settings.downloadedModelName';
  static const huggingFaceToken = 'settings.huggingFaceToken';
  static const imageQuality = 'settings.imageQuality';
  static const aiContextItems = 'settings.aiContextItems';
  static const aiContextWindowTokens = 'settings.aiContextWindowTokens';
  static const localEndpoint = 'settings.localEndpoint';
  static const localServerModel = 'settings.localServerModel';
  static const cloudAiProvider = 'settings.cloudAiProvider';
  static const cloudEndpoint = 'settings.cloudEndpoint';
  static const cloudModel = 'settings.cloudModel';
  static const cloudApiKey = 'settings.cloudApiKey';
  static const steamApiKey = 'settings.steamApiKey';
}

class LocalAiRuntimeSettings {
  final bool useLocalAi;
  final bool useAiForSearch;
  final String mode;
  final String provider;
  final String endpoint;
  final String serverModel;
  final String cloudProvider;
  final String cloudEndpoint;
  final String cloudModel;
  final String cloudApiKey;
  final String deviceModelName;
  final String backend;
  final double contextItems;
  final int? contextWindowOverrideTokens;
  final bool allowExplicitContent;

  const LocalAiRuntimeSettings({
    required this.useLocalAi,
    required this.useAiForSearch,
    this.mode = localAiModeRulesOnly,
    required this.provider,
    required this.endpoint,
    required this.serverModel,
    this.cloudProvider = defaultCloudAiProvider,
    this.cloudEndpoint = defaultCloudAiEndpoint,
    this.cloudModel = defaultCloudAiModel,
    this.cloudApiKey = '',
    this.deviceModelName = '',
    this.backend = localAiBackendAuto,
    required this.contextItems,
    this.contextWindowOverrideTokens,
    this.allowExplicitContent = false,
  });

  const LocalAiRuntimeSettings.defaults({bool enabled = false})
    : useLocalAi = enabled,
      useAiForSearch = true,
      mode = enabled ? localAiModeOnDevice : localAiModeRulesOnly,
      provider = fallbackRulesProvider,
      endpoint = defaultLocalAiEndpoint,
      serverModel = defaultLocalAiModel,
      cloudProvider = defaultCloudAiProvider,
      cloudEndpoint = defaultCloudAiEndpoint,
      cloudModel = defaultCloudAiModel,
      cloudApiKey = '',
      deviceModelName = '',
      backend = localAiBackendAuto,
      contextItems = 24,
      contextWindowOverrideTokens = null,
      allowExplicitContent = false;

  bool get usesExternalServer =>
      useLocalAi &&
      mode == localAiModeExternalServer &&
      endpoint.trim().isNotEmpty;

  bool get usesExternalCloud =>
      useLocalAi &&
      mode == localAiModeExternalCloud &&
      cloudEndpoint.trim().isNotEmpty;

  bool get usesManualAi => useLocalAi && mode == localAiModeManual;

  bool get usesOnDeviceModel =>
      useLocalAi &&
      mode == localAiModeOnDevice &&
      !usesExternalServer &&
      !usesExternalCloud &&
      !usesManualAi;

  int get contextItemLimit => contextItems.round().clamp(8, 48);

  int get contextWindowTokens {
    final override = contextWindowOverrideTokens;
    if (override != null) {
      return override.clamp(
        minimumAiContextWindowTokens,
        maximumAiContextWindowTokens,
      );
    }
    return resolveAiContextWindowTokens(
      mode: mode,
      modelName: activeModelName,
      cloudProvider: usesExternalCloud ? cloudProvider : '',
    );
  }

  String get activeModelName {
    if (usesExternalCloud) return cloudModel;
    if (usesExternalServer) return serverModel;
    if (usesOnDeviceModel) return deviceModelName;
    return provider;
  }

  PreferredBackend? get preferredBackend {
    return switch (backend) {
      localAiBackendCpu => PreferredBackend.cpu,
      localAiBackendGpu => PreferredBackend.gpu,
      localAiBackendNpu => PreferredBackend.npu,
      _ => null,
    };
  }

  Uri get localChatCompletionsUri => _chatCompletionsUri(endpoint);

  Uri get cloudChatCompletionsUri => _chatCompletionsUri(cloudEndpoint);

  Uri _chatCompletionsUri(String value) {
    final parsed = Uri.parse(value.trim());
    final path = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;

    if (path.endsWith('/chat/completions')) return parsed;
    if (path.endsWith('/v1')) {
      return parsed.replace(path: '$path/chat/completions');
    }
    if (path.endsWith('/openai')) {
      return parsed.replace(path: '$path/chat/completions');
    }
    return parsed.replace(path: '$path/v1/chat/completions');
  }

  static Future<LocalAiRuntimeSettings> load({
    bool defaultEnabled = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final legacyProvider = prefs.getString(LocalAiSettingsKeys.localAiProvider);
    final mode =
        prefs.getString(LocalAiSettingsKeys.localAiMode) ??
        _modeFromLegacyProvider(legacyProvider);
    final useLocalAi =
        prefs.getBool(LocalAiSettingsKeys.useLocalAi) ??
        (defaultEnabled ||
            mode == localAiModeOnDevice ||
            mode == localAiModeExternalServer ||
            mode == localAiModeExternalCloud ||
            mode == localAiModeManual);

    return LocalAiRuntimeSettings(
      useLocalAi: mode == localAiModeRulesOnly ? false : useLocalAi,
      useAiForSearch: prefs.getBool(LocalAiSettingsKeys.useAiForSearch) ?? true,
      mode: mode,
      provider: legacyProvider ?? fallbackRulesProvider,
      endpoint:
          prefs.getString(LocalAiSettingsKeys.localEndpoint) ??
          defaultLocalAiEndpoint,
      serverModel:
          prefs.getString(LocalAiSettingsKeys.localServerModel) ??
          defaultLocalAiModel,
      cloudProvider:
          prefs.getString(LocalAiSettingsKeys.cloudAiProvider) ??
          defaultCloudAiProvider,
      cloudEndpoint:
          prefs.getString(LocalAiSettingsKeys.cloudEndpoint) ??
          defaultCloudAiEndpoint,
      cloudModel:
          prefs.getString(LocalAiSettingsKeys.cloudModel) ??
          defaultCloudAiModel,
      cloudApiKey: prefs.getString(LocalAiSettingsKeys.cloudApiKey) ?? '',
      deviceModelName:
          prefs.getString(LocalAiSettingsKeys.selectedModelName) ??
          prefs.getString(LocalAiSettingsKeys.downloadedModelName) ??
          '',
      backend:
          prefs.getString(LocalAiSettingsKeys.localBackend) ??
          localAiBackendAuto,
      contextItems: prefs.getDouble(LocalAiSettingsKeys.aiContextItems) ?? 24,
      contextWindowOverrideTokens: prefs.getInt(
        LocalAiSettingsKeys.aiContextWindowTokens,
      ),
      allowExplicitContent:
          prefs.getBool(LocalAiSettingsKeys.allowExplicitContent) ?? false,
    );
  }

  static String _modeFromLegacyProvider(String? provider) {
    return switch (provider) {
      externalLocalAiProvider => localAiModeExternalServer,
      externalCloudAiProvider => localAiModeExternalCloud,
      localAiModeManual => localAiModeManual,
      fallbackRulesProvider => localAiModeRulesOnly,
      null => localAiModeRulesOnly,
      _ => localAiModeOnDevice,
    };
  }
}

int resolveAiContextWindowTokens({
  required String mode,
  required String modelName,
  String cloudProvider = '',
}) {
  final normalized = '$cloudProvider $modelName'.toLowerCase();
  if (mode == localAiModeManual) return defaultManualContextWindowTokens;

  if (normalized.contains('gemini')) return 1048576;
  if (normalized.contains('llama-3.1') ||
      normalized.contains('llama3.1') ||
      normalized.contains('llama-3.2') ||
      normalized.contains('llama3.2')) {
    return 131072;
  }

  if (normalized.contains('gemma 3n') ||
      normalized.contains('gemma3n') ||
      normalized.contains('qwen3:4b') ||
      normalized.contains('qwen3:8b') ||
      normalized.contains('gemma3:4b') ||
      normalized.contains('gemma3:12b')) {
    return 32768;
  }

  if (mode == localAiModeExternalCloud) {
    return defaultCloudContextWindowTokens;
  }
  if (mode == localAiModeExternalServer) {
    return defaultLocalServerContextWindowTokens;
  }
  return defaultOnDeviceContextWindowTokens;
}

String formatAiTokenCount(int tokens) {
  if (tokens >= 1048576 && tokens % 1048576 == 0) {
    return '${tokens ~/ 1048576}M';
  }
  if (tokens >= 1024 && tokens % 1024 == 0) return '${tokens ~/ 1024}K';
  return tokens.toString();
}
