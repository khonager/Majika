import 'package:shared_preferences/shared_preferences.dart';

const externalLocalAiProvider = 'External local server';
const fallbackRulesProvider = 'Fallback rules only';
const localAiModeOnDevice = 'Automatic on-device';
const localAiModeExternalServer = externalLocalAiProvider;
const localAiModeRulesOnly = fallbackRulesProvider;
const defaultLocalAiEndpoint = 'http://127.0.0.1:52625/v1/chat/completions';
const defaultLocalAiModel = 'gemma3:4b';

class LocalAiSettingsKeys {
  static const immersiveReader = 'settings.immersiveReader';
  static const downloadOnWifiOnly = 'settings.downloadOnWifiOnly';
  static const allowExplicitContent = 'settings.allowExplicitContent';
  static const enableMotionEffects = 'settings.enableMotionEffects';
  static const useLocalAi = 'settings.useLocalAi';
  static const useAiForSearch = 'settings.useAiForSearch';
  static const localAiMode = 'settings.localAiMode';
  static const localAiProvider = 'settings.localAiProvider';
  static const selectedModelId = 'settings.selectedModelId';
  static const selectedModelName = 'settings.selectedModelName';
  static const downloadedModelId = 'settings.downloadedModelId';
  static const downloadedModelName = 'settings.downloadedModelName';
  static const imageQuality = 'settings.imageQuality';
  static const aiContextItems = 'settings.aiContextItems';
  static const localEndpoint = 'settings.localEndpoint';
  static const localServerModel = 'settings.localServerModel';
}

class LocalAiRuntimeSettings {
  final bool useLocalAi;
  final bool useAiForSearch;
  final String mode;
  final String provider;
  final String endpoint;
  final String serverModel;
  final double contextItems;

  const LocalAiRuntimeSettings({
    required this.useLocalAi,
    required this.useAiForSearch,
    this.mode = localAiModeRulesOnly,
    required this.provider,
    required this.endpoint,
    required this.serverModel,
    required this.contextItems,
  });

  const LocalAiRuntimeSettings.defaults({bool enabled = false})
    : useLocalAi = enabled,
      useAiForSearch = true,
      mode = enabled ? localAiModeOnDevice : localAiModeRulesOnly,
      provider = fallbackRulesProvider,
      endpoint = defaultLocalAiEndpoint,
      serverModel = defaultLocalAiModel,
      contextItems = 24;

  bool get usesExternalServer =>
      useLocalAi &&
      mode == localAiModeExternalServer &&
      endpoint.trim().isNotEmpty;

  bool get usesOnDeviceModel =>
      useLocalAi && mode == localAiModeOnDevice && !usesExternalServer;

  int get contextItemLimit => contextItems.round().clamp(8, 48);

  Uri get chatCompletionsUri {
    final parsed = Uri.parse(endpoint.trim());
    final path = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;

    if (path.endsWith('/chat/completions')) return parsed;
    if (path.endsWith('/v1')) {
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
            mode == localAiModeExternalServer);

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
      contextItems: prefs.getDouble(LocalAiSettingsKeys.aiContextItems) ?? 24,
    );
  }

  static String _modeFromLegacyProvider(String? provider) {
    return switch (provider) {
      externalLocalAiProvider => localAiModeExternalServer,
      fallbackRulesProvider => localAiModeRulesOnly,
      null => localAiModeRulesOnly,
      _ => localAiModeOnDevice,
    };
  }
}
