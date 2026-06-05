import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/firebase/firebase_profile_service.dart';
import 'package:majika/ui/profile/profile_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:majika/ui/shared/glass_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _desktopOnDevicePlatforms = {
  TargetPlatform.linux,
  TargetPlatform.macOS,
  TargetPlatform.windows,
};
const _mobileOnDevicePlatforms = {TargetPlatform.android, TargetPlatform.iOS};
const _onDevicePlatforms = {
  ..._mobileOnDevicePlatforms,
  ..._desktopOnDevicePlatforms,
};

enum _AiModelTier {
  low('Experimental small', Icons.science_rounded),
  recommended('Benchmark candidate', Icons.auto_awesome_rounded),
  high('High-context candidate', Icons.workspace_premium_rounded);

  final String label;
  final IconData icon;

  const _AiModelTier(this.label, this.icon);
}

enum _ServerRuntime {
  ollama('Ollama', defaultLocalAiEndpoint, Icons.terminal_rounded),
  fastFlowLm('FastFlowLM', _flmLocalAiEndpoint, Icons.memory_rounded);

  final String label;
  final String endpoint;
  final IconData icon;

  const _ServerRuntime(this.label, this.endpoint, this.icon);
}

const _downloadableLocalAiModels = [
  _DownloadableModel(
    id: 'gemma3_1b_it',
    name: 'Gemma 3 1B IT',
    sizeLabel: '586 MB',
    providerLabel: 'Gemma',
    tier: _AiModelTier.low,
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
    supportedPlatforms: _onDevicePlatforms,
  ),
  _DownloadableModel(
    id: 'gemma3n_e2b_it',
    name: 'Gemma 3n E2B IT',
    sizeLabel: '3.1 GB',
    providerLabel: 'Gemma',
    tier: _AiModelTier.recommended,
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
    supportedPlatforms: _onDevicePlatforms,
  ),
  _DownloadableModel(
    id: 'gemma3n_e4b_it',
    name: 'Gemma 3n E4B IT',
    sizeLabel: '6.5 GB',
    providerLabel: 'Gemma',
    tier: _AiModelTier.high,
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
    supportedPlatforms: _onDevicePlatforms,
  ),
  _DownloadableModel(
    id: 'qwen3_0_6b',
    name: 'Qwen3 0.6B',
    sizeLabel: '586 MB',
    providerLabel: 'Qwen',
    tier: _AiModelTier.low,
    resourceLabel: 'Balanced public text model',
    mobileUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    description:
        'Tiny public alternative. Keep experimental until benchmarks show it can follow Majika recommendation prompts.',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    isAdvanced: true,
    supportedPlatforms: _desktopOnDevicePlatforms,
  ),
  _DownloadableModel(
    id: 'deepseek_r1_qwen_1_5b',
    name: 'DeepSeek R1 Distill Qwen 1.5B',
    sizeLabel: '1.7 GB',
    providerLabel: 'DeepSeek',
    tier: _AiModelTier.high,
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
  _DownloadableModel(
    id: 'qwen25_1_5b_instruct',
    name: 'Qwen 2.5 1.5B Instruct',
    sizeLabel: '1.6 GB',
    providerLabel: 'Qwen',
    tier: _AiModelTier.recommended,
    resourceLabel: 'Advanced public text model',
    mobileUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    description:
        'Larger candidate to benchmark against Qwen3 before recommending.',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    isAdvanced: true,
    supportedPlatforms: _desktopOnDevicePlatforms,
  ),
];

final _defaultLocalAiModel = _downloadableLocalAiModels.firstWhere(
  (model) => model.tier == _AiModelTier.recommended,
  orElse: () => _downloadableLocalAiModels.first,
);
const _flmLocalAiEndpoint = 'http://127.0.0.1:52625/v1/chat/completions';
const _flmDefaultModel = 'llama3.2:1b';
const _externalLocalServerModelPresets = [
  _ServerModelPreset(
    name: 'llama3.2:1b',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.low,
    sizeLabel: '1.3 GB',
    description:
        'Smallest useful Ollama fallback for modest laptops. It uses compact prompts and is best when speed matters more than rich explanations.',
  ),
  _ServerModelPreset(
    name: 'llama3.2:3b',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.recommended,
    sizeLabel: '2.0 GB',
    description:
        'Good starter model for Majika on everyday machines: stronger than 1B while still light enough to run locally.',
  ),
  _ServerModelPreset(
    name: 'qwen2.5:3b-instruct',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.recommended,
    sizeLabel: '1.9 GB',
    description:
        'Compact instruction-following model that tends to handle structured recommendation prompts cleanly.',
  ),
  _ServerModelPreset(
    name: 'qwen2.5:7b-instruct',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.high,
    sizeLabel: '4.7 GB',
    description:
        'Higher-quality local choice for ranking, tag filtering, and explanation quality when RAM is available.',
  ),
  _ServerModelPreset(
    name: 'qwen3:4b-instruct',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.recommended,
    sizeLabel: '2.5 GB',
    description:
        'Majika default local-server model: strong instruction following without being too heavy.',
  ),
  _ServerModelPreset(
    name: 'gemma3:1b',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.low,
    sizeLabel: '815 MB',
    description:
        'Experimental compact-prompt fallback; keep larger models preferred when recommendation quality matters.',
  ),
  _ServerModelPreset(
    name: 'gemma3:4b',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.recommended,
    sizeLabel: '3.3 GB',
    description: 'Balanced Gemma option for local server users.',
  ),
  _ServerModelPreset(
    name: 'llama3.1:8b',
    runtime: _ServerRuntime.ollama,
    tier: _AiModelTier.high,
    sizeLabel: '4.9 GB',
    description:
        'Reliable installed-friendly generalist for fuller recommendation reasoning on larger local machines.',
  ),
  _ServerModelPreset(
    name: 'qwen3:0.6b',
    runtime: _ServerRuntime.fastFlowLm,
    tier: _AiModelTier.low,
    sizeLabel: 'FLM',
    description:
        'FastFlowLM compact model for Ryzen AI NPU setups. Use when FLM is installed and you want the lightest server option.',
  ),
  _ServerModelPreset(
    name: 'qwen3:4b',
    runtime: _ServerRuntime.fastFlowLm,
    tier: _AiModelTier.recommended,
    sizeLabel: 'FLM',
    description:
        'FastFlowLM balanced NPU option for Majika-style structured prompts on supported Ryzen AI devices.',
  ),
  _ServerModelPreset(
    name: _flmDefaultModel,
    runtime: _ServerRuntime.fastFlowLm,
    tier: _AiModelTier.low,
    sizeLabel: 'FastFlowLM',
    description: 'FastFlowLM starter model for AMD NPU-oriented setups.',
  ),
];

const _externalCloudAiPresets = [
  _CloudAiProviderPreset(
    provider: 'Google Gemini',
    endpoint:
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    model: 'gemini-3.1-flash-lite',
    tier: _AiModelTier.recommended,
    freeLabel: 'Free Gemini API tier',
    keyUrl: 'https://aistudio.google.com/app/apikey',
    description:
        'Best default cloud fallback for Majika: low-cost search interpretation and recommendation explanations through Google AI Studio.',
  ),
  _CloudAiProviderPreset(
    provider: 'Groq',
    endpoint: 'https://api.groq.com/openai/v1',
    model: 'llama-3.1-8b-instant',
    tier: _AiModelTier.low,
    freeLabel: 'Free developer limits',
    keyUrl: 'https://console.groq.com/keys',
    description:
        'Very fast OpenAI-compatible API for lightweight structured prompts when local hardware is not enough.',
  ),
  _CloudAiProviderPreset(
    provider: 'OpenRouter',
    endpoint: 'https://openrouter.ai/api/v1',
    model: 'meta-llama/llama-3.2-3b-instruct:free',
    tier: _AiModelTier.low,
    freeLabel: 'Free :free model variants',
    keyUrl: 'https://openrouter.ai/settings/keys',
    description:
        'Aggregator option for users who want a rotating catalog of free models. Use model IDs ending in :free to avoid paid routing.',
  ),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _immersiveReader = true;
  bool _downloadOnWifiOnly = true;
  bool _allowExplicitContent = false;
  bool _enableMotionEffects = true;
  bool _useLocalAi = false;
  bool _useAiForSearch = true;
  bool _isDownloadingModel = false;
  bool _isDeletingModel = false;
  bool _showAdvancedLocalAi = false;
  String _localAiMode = localAiModeRulesOnly;
  String _localBackend = localAiBackendAuto;
  String _localAiProvider = _defaultLocalAiModel.providerLabel;
  _DownloadableModel _selectedModel = _defaultLocalAiModel;
  String? _downloadedModelId;
  String? _downloadedModelName;
  bool _isLoadingServerModels = false;
  String? _serverModelStatusMessage;
  Set<String> _installedOllamaModels = const {};
  double _imageQuality = 0.85;
  double? _downloadProgress;
  CancelToken? _downloadCancelToken;
  final _localEndpointController = TextEditingController(
    text: defaultLocalAiEndpoint,
  );
  final _localServerModelController = TextEditingController(
    text: defaultLocalAiModel,
  );
  final _cloudEndpointController = TextEditingController(
    text: defaultCloudAiEndpoint,
  );
  final _cloudModelController = TextEditingController(
    text: defaultCloudAiModel,
  );
  final _cloudApiKeyController = TextEditingController();
  final _contextWindowController = TextEditingController();
  final _huggingFaceTokenController = TextEditingController();
  Timer? _huggingFaceTokenSyncTimer;

  bool get _hasDownloadedModel =>
      _downloadedModelId != null || _downloadedModelName != null;

  bool get _usesOnDeviceAi => _localAiMode == localAiModeOnDevice;

  bool get _usesExternalServer => _localAiMode == localAiModeExternalServer;

  bool get _usesExternalCloud => _localAiMode == localAiModeExternalCloud;

  bool get _supportsOnDeviceAi =>
      !kIsWeb && _onDevicePlatforms.contains(defaultTargetPlatform);

  List<String> get _localAiModeOptions => [
    if (_supportsOnDeviceAi) localAiModeOnDevice,
    localAiModeExternalServer,
    localAiModeExternalCloud,
    localAiModeManual,
    localAiModeRulesOnly,
  ];

  List<_DownloadableModel> get _availableLocalAiModels =>
      _downloadableLocalAiModels
          .where((model) => model.supportsCurrentPlatform)
          .toList();

  List<_DownloadableModel> get _visibleLocalAiModels {
    return _availableLocalAiModels.isEmpty
        ? [_defaultLocalAiModel]
        : _availableLocalAiModels;
  }

  _DownloadableModel get _effectiveSelectedModel {
    final models = _visibleLocalAiModels;
    return models.contains(_selectedModel) ? _selectedModel : models.first;
  }

  List<_ServerModelPreset> get _serverModelPresets {
    final presets = [..._externalLocalServerModelPresets];
    final knownNames = presets.map((preset) => preset.name).toSet();
    final installedOnly =
        _installedOllamaModels
            .where((name) => !knownNames.contains(name))
            .where((name) => !_looksLikeEmbeddingModel(name))
            .toList()
          ..sort();
    for (final name in installedOnly) {
      presets.insert(
        0,
        _ServerModelPreset(
          name: name,
          runtime: _ServerRuntime.ollama,
          tier: _AiModelTier.recommended,
          sizeLabel: 'Installed',
          description:
              'Installed Ollama model found on this device. Majika can use it immediately; benchmark quality before making it your default.',
        ),
      );
    }
    return presets;
  }

  _ServerModelPreset get _effectiveServerModelPreset {
    final modelName = _localServerModelController.text.trim();
    for (final preset in _serverModelPresets) {
      if (preset.name == modelName) return preset;
    }
    return _serverModelPresets.firstWhere(
      (preset) => preset.name == defaultLocalAiModel,
      orElse: () => _serverModelPresets.first,
    );
  }

  String get _effectiveServerModelName {
    final modelName = _localServerModelController.text.trim();
    return modelName.isEmpty ? defaultLocalAiModel : modelName;
  }

  _CloudAiProviderPreset get _effectiveCloudProviderPreset {
    for (final preset in _externalCloudAiPresets) {
      if (preset.provider == _localAiProvider) return preset;
    }
    return _externalCloudAiPresets.first;
  }

  String get _ollamaServeCommand => 'ollama run $_effectiveServerModelName';

  String get _ollamaPullCommand => 'ollama pull $_effectiveServerModelName';

  String get _effectiveFlmModelName =>
      _effectiveServerModelPreset.runtime == _ServerRuntime.fastFlowLm
      ? _effectiveServerModelName
      : _flmDefaultModel;

  String get _flmServeCommand => 'flm serve $_effectiveFlmModelName';

  String get _flmPullCommand => 'flm pull $_effectiveFlmModelName';

  int get _resolvedContextWindowTokens {
    final override = int.tryParse(_contextWindowController.text.trim());
    if (override != null) {
      return override.clamp(
        minimumAiContextWindowTokens,
        maximumAiContextWindowTokens,
      );
    }
    final modelName = switch (_localAiMode) {
      localAiModeExternalCloud => _cloudModelController.text.trim(),
      localAiModeExternalServer => _effectiveServerModelName,
      localAiModeOnDevice =>
        _downloadedModelName ?? _effectiveSelectedModel.name,
      _ => '',
    };
    return resolveAiContextWindowTokens(
      mode: _localAiMode,
      modelName: modelName,
      cloudProvider: _localAiProvider,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final selectedModelId = prefs.getString(
      LocalAiSettingsKeys.selectedModelId,
    );
    final selectedModelName = prefs.getString(
      LocalAiSettingsKeys.selectedModelName,
    );
    _DownloadableModel? selectedModel;
    for (final model in _downloadableLocalAiModels) {
      if (model.id == selectedModelId || model.name == selectedModelName) {
        selectedModel = model;
        break;
      }
    }
    final legacyProvider = prefs.getString(LocalAiSettingsKeys.localAiProvider);
    final savedMode =
        prefs.getString(LocalAiSettingsKeys.localAiMode) ??
        _modeFromLegacyProvider(legacyProvider);
    final normalizedMode =
        savedMode == localAiModeOnDevice && !_supportsOnDeviceAi
        ? localAiModeExternalServer
        : savedMode;

    setState(() {
      _immersiveReader =
          prefs.getBool(LocalAiSettingsKeys.immersiveReader) ??
          _immersiveReader;
      _downloadOnWifiOnly =
          prefs.getBool(LocalAiSettingsKeys.downloadOnWifiOnly) ??
          _downloadOnWifiOnly;
      _allowExplicitContent =
          prefs.getBool(LocalAiSettingsKeys.allowExplicitContent) ??
          _allowExplicitContent;
      _enableMotionEffects =
          prefs.getBool(LocalAiSettingsKeys.enableMotionEffects) ??
          _enableMotionEffects;
      _useLocalAi =
          prefs.getBool(LocalAiSettingsKeys.useLocalAi) ??
          (normalizedMode == localAiModeOnDevice ||
              normalizedMode == localAiModeExternalServer ||
              normalizedMode == localAiModeExternalCloud ||
              normalizedMode == localAiModeManual);
      _useAiForSearch =
          prefs.getBool(LocalAiSettingsKeys.useAiForSearch) ?? _useAiForSearch;
      _localAiMode = normalizedMode;
      _localBackend =
          prefs.getString(LocalAiSettingsKeys.localBackend) ??
          localAiBackendAuto;
      if (_localAiMode == localAiModeRulesOnly) {
        _useLocalAi = false;
      }
      _localAiProvider = normalizedMode == localAiModeExternalCloud
          ? (prefs.getString(LocalAiSettingsKeys.cloudAiProvider) ??
                defaultCloudAiProvider)
          : (legacyProvider ??
                selectedModel?.providerLabel ??
                _localAiProvider);
      _selectedModel = selectedModel ?? _selectedModel;
      _downloadedModelId = prefs.getString(
        LocalAiSettingsKeys.downloadedModelId,
      );
      _downloadedModelName = prefs.getString(
        LocalAiSettingsKeys.downloadedModelName,
      );
      _imageQuality =
          prefs.getDouble(LocalAiSettingsKeys.imageQuality) ?? _imageQuality;
      _contextWindowController.text =
          prefs.getInt(LocalAiSettingsKeys.aiContextWindowTokens)?.toString() ??
          '';
      _localEndpointController.text =
          prefs.getString(LocalAiSettingsKeys.localEndpoint) ??
          _localEndpointController.text;
      _localServerModelController.text =
          prefs.getString(LocalAiSettingsKeys.localServerModel) ??
          _localServerModelController.text;
      _cloudEndpointController.text =
          prefs.getString(LocalAiSettingsKeys.cloudEndpoint) ??
          _cloudEndpointController.text;
      _cloudModelController.text =
          prefs.getString(LocalAiSettingsKeys.cloudModel) ??
          _cloudModelController.text;
      _cloudApiKeyController.text =
          prefs.getString(LocalAiSettingsKeys.cloudApiKey) ?? '';
      _huggingFaceTokenController.text =
          prefs.getString(LocalAiSettingsKeys.huggingFaceToken) ?? '';
    });
    _loadProfileHuggingFaceTokenIfNeeded();
    unawaited(_refreshServerModels());
  }

  String _modeFromLegacyProvider(String? provider) {
    return switch (provider) {
      externalLocalAiProvider => localAiModeExternalServer,
      externalCloudAiProvider => localAiModeExternalCloud,
      localAiModeManual => localAiModeManual,
      fallbackRulesProvider => localAiModeRulesOnly,
      null => localAiModeRulesOnly,
      _ => localAiModeOnDevice,
    };
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveContextWindowOverride(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      await prefs.remove(LocalAiSettingsKeys.aiContextWindowTokens);
      return;
    }
    await prefs.setInt(
      LocalAiSettingsKeys.aiContextWindowTokens,
      parsed.clamp(minimumAiContextWindowTokens, maximumAiContextWindowTokens),
    );
  }

  Future<void> _copyServerCommand(String label, String command) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    showInfoToast(context, '$label command copied.');
  }

  Future<void> _refreshServerModels() async {
    final endpoint = _localEndpointController.text.trim().isEmpty
        ? defaultLocalAiEndpoint
        : _localEndpointController.text.trim();
    if (!_looksLikeOllamaEndpoint(endpoint)) {
      if (!mounted) return;
      setState(() {
        _installedOllamaModels = const {};
        _serverModelStatusMessage =
            'FastFlowLM is not installed on this device. Use flm list on a supported Windows Ryzen AI setup to confirm downloaded models.';
      });
      return;
    }

    setState(() {
      _isLoadingServerModels = true;
      _serverModelStatusMessage = null;
    });

    try {
      final tagsUri = _ollamaTagsUri(endpoint);
      final response = await http
          .get(tagsUri)
          .timeout(const Duration(milliseconds: 1800));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Ollama returned HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      final models = decoded is Map<String, dynamic> ? decoded['models'] : null;
      final names = <String>{};
      if (models is List) {
        for (final model in models) {
          if (model is! Map<String, dynamic>) continue;
          final name = model['name'] ?? model['model'];
          if (name != null) names.add(name.toString());
        }
      }
      if (!mounted) return;
      setState(() {
        _installedOllamaModels = names;
        _serverModelStatusMessage = names.isEmpty
            ? 'Ollama is reachable, but no downloaded models were reported.'
            : 'Found ${names.length} downloaded Ollama model${names.length == 1 ? '' : 's'} on this device.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installedOllamaModels = const {};
        _serverModelStatusMessage =
            'Could not reach Ollama at ${_ollamaTagsUri(endpoint)}. Start Ollama, then refresh.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingServerModels = false);
      }
    }
  }

  Future<void> _useOllamaDefaults() async {
    final modelName = _effectiveServerModelName == _flmDefaultModel
        ? defaultLocalAiModel
        : _effectiveServerModelName;
    setState(() {
      _localEndpointController.text = defaultLocalAiEndpoint;
      _localServerModelController.text = modelName;
      _localAiMode = localAiModeExternalServer;
      _useLocalAi = true;
      _localAiProvider = localAiModeExternalServer;
    });
    await _saveString(
      LocalAiSettingsKeys.localEndpoint,
      defaultLocalAiEndpoint,
    );
    await _saveString(LocalAiSettingsKeys.localServerModel, modelName);
    await _saveString(
      LocalAiSettingsKeys.localAiMode,
      localAiModeExternalServer,
    );
    await _saveBool(LocalAiSettingsKeys.useLocalAi, true);
    unawaited(_refreshServerModels());
  }

  Future<void> _useFlmDefaults() async {
    setState(() {
      _localEndpointController.text = _flmLocalAiEndpoint;
      _localServerModelController.text = _flmDefaultModel;
      _localAiMode = localAiModeExternalServer;
      _useLocalAi = true;
      _localAiProvider = localAiModeExternalServer;
    });
    await _saveString(LocalAiSettingsKeys.localEndpoint, _flmLocalAiEndpoint);
    await _saveString(LocalAiSettingsKeys.localServerModel, _flmDefaultModel);
    await _saveString(
      LocalAiSettingsKeys.localAiMode,
      localAiModeExternalServer,
    );
    await _saveBool(LocalAiSettingsKeys.useLocalAi, true);
    unawaited(_refreshServerModels());
  }

  Future<void> _useCloudProvider(_CloudAiProviderPreset preset) async {
    setState(() {
      _localAiMode = localAiModeExternalCloud;
      _useLocalAi = true;
      _localAiProvider = preset.provider;
      _cloudEndpointController.text = preset.endpoint;
      _cloudModelController.text = preset.model;
    });
    await _saveString(
      LocalAiSettingsKeys.localAiMode,
      localAiModeExternalCloud,
    );
    await _saveBool(LocalAiSettingsKeys.useLocalAi, true);
    await _saveString(
      LocalAiSettingsKeys.localAiProvider,
      externalCloudAiProvider,
    );
    await _saveString(LocalAiSettingsKeys.cloudAiProvider, preset.provider);
    await _saveString(LocalAiSettingsKeys.cloudEndpoint, preset.endpoint);
    await _saveString(LocalAiSettingsKeys.cloudModel, preset.model);
  }

  Future<void> _saveDownloadedModel(_DownloadableModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalAiSettingsKeys.downloadedModelId, model.id);
    await prefs.setString(LocalAiSettingsKeys.downloadedModelName, model.name);
    await prefs.setString(LocalAiSettingsKeys.selectedModelId, model.id);
    await prefs.setString(LocalAiSettingsKeys.selectedModelName, model.name);
    await prefs.setBool(LocalAiSettingsKeys.useLocalAi, true);
    await prefs.setString(LocalAiSettingsKeys.localAiMode, localAiModeOnDevice);
    await prefs.setString(
      LocalAiSettingsKeys.localAiProvider,
      model.providerLabel,
    );
  }

  Future<void> _clearDownloadedModelSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(LocalAiSettingsKeys.downloadedModelId);
    await prefs.remove(LocalAiSettingsKeys.downloadedModelName);
    await prefs.setBool(LocalAiSettingsKeys.useLocalAi, false);
    await prefs.setString(
      LocalAiSettingsKeys.localAiMode,
      localAiModeRulesOnly,
    );
    await prefs.setString(
      LocalAiSettingsKeys.localAiProvider,
      fallbackRulesProvider,
    );
  }

  Future<void> _loadProfileHuggingFaceTokenIfNeeded() async {
    if (_huggingFaceTokenController.text.trim().isNotEmpty) return;
    try {
      final profile = await const FirebaseProfileService().fetchProfile();
      final token = profile?.huggingFaceToken?.trim();
      if (!mounted || token == null || token.isEmpty) return;
      setState(() => _huggingFaceTokenController.text = token);
      await _saveString(LocalAiSettingsKeys.huggingFaceToken, token);
    } catch (_) {
      // Profile sync is optional; local-only use should not be blocked.
    }
  }

  Future<void> _saveHuggingFaceToken(String value) async {
    await _saveString(LocalAiSettingsKeys.huggingFaceToken, value.trim());
    _huggingFaceTokenSyncTimer?.cancel();
    _huggingFaceTokenSyncTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_syncHuggingFaceTokenToProfile(value));
    });
  }

  Future<void> _syncHuggingFaceTokenToProfile(String value) async {
    try {
      await const FirebaseProfileService().saveHuggingFaceTokenIfSignedIn(
        value,
      );
    } catch (_) {
      // Keep token local if profile sync is unavailable or the user is signed out.
    }
  }

  Future<void> _downloadRecommendedModel() async {
    if (_isDownloadingModel) return;

    final cancelToken = CancelToken();
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = null;
      _downloadCancelToken = cancelToken;
    });

    final modelToDownload = _effectiveSelectedModel;
    try {
      final huggingFaceToken = _huggingFaceTokenController.text.trim();
      if (modelToDownload.needsHuggingFaceToken && huggingFaceToken.isEmpty) {
        throw const _HuggingFaceTokenRequiredException();
      }

      await FlutterGemma.initialize(
        huggingFaceToken: huggingFaceToken.isEmpty ? null : huggingFaceToken,
      );
      final installation =
          await FlutterGemma.installModel(
                modelType: modelToDownload.modelType,
                fileType: modelToDownload.fileType,
              )
              .fromNetwork(
                modelToDownload.url,
                token: modelToDownload.needsHuggingFaceToken
                    ? huggingFaceToken
                    : null,
                foreground: true,
              )
              .withCancelToken(cancelToken)
              .withProgress((progress) {
                if (mounted && !cancelToken.isCancelled) {
                  setState(() => _downloadProgress = progress / 100);
                }
              })
              .install();

      if (!mounted ||
          cancelToken.isCancelled ||
          _downloadCancelToken != cancelToken) {
        return;
      }
      setState(() {
        _downloadedModelId = modelToDownload.id;
        _downloadedModelName = modelToDownload.name;
        _useLocalAi = true;
        _localAiMode = localAiModeOnDevice;
        _localAiProvider = modelToDownload.providerLabel;
        _downloadProgress = 1;
      });
      await _saveDownloadedModel(modelToDownload);
      if (!mounted) return;
      showInfoToast(
        context,
        '${installation.modelId} downloaded and activated.',
      );
    } catch (error) {
      if (!mounted) return;
      if (CancelToken.isCancel(error) || cancelToken.isCancelled) return;
      final message = _downloadModelErrorMessage(error, modelToDownload);
      showErrorToast(context, message);
    } finally {
      if (mounted && _downloadCancelToken == cancelToken) {
        setState(() {
          _isDownloadingModel = false;
          _downloadCancelToken = null;
          if (cancelToken.isCancelled) _downloadProgress = null;
        });
      }
    }
  }

  void _cancelModelDownload() {
    final cancelToken = _downloadCancelToken;
    if (cancelToken == null || cancelToken.isCancelled) return;
    cancelToken.cancel('Model download canceled by user.');
    setState(() {
      _isDownloadingModel = false;
      _downloadProgress = null;
    });
    showInfoToast(context, 'Model download canceled.');
  }

  Future<void> _deleteDownloadedModel() async {
    if (_isDownloadingModel || _isDeletingModel) return;
    final modelToDelete = _effectiveSelectedModel;
    final isDownloaded =
        _downloadedModelId == modelToDelete.id ||
        _downloadedModelName == modelToDelete.name;
    if (!isDownloaded) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text(
          'Remove ${modelToDelete.name} from this device. Majika will use rules only until another model is installed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingModel = true);
    try {
      await FlutterGemma.uninstallModel(modelToDelete.storageFileName);
      if (!mounted) return;
      setState(() {
        _downloadedModelId = null;
        _downloadedModelName = null;
        _useLocalAi = false;
        _localAiMode = localAiModeRulesOnly;
        _localAiProvider = fallbackRulesProvider;
        _downloadProgress = null;
      });
      await _clearDownloadedModelSettings();
      if (!mounted) return;
      showInfoToast(context, '${modelToDelete.name} deleted.');
    } catch (error) {
      if (!mounted) return;
      if (error.toString().contains('Model not found')) {
        setState(() {
          _downloadedModelId = null;
          _downloadedModelName = null;
          _useLocalAi = false;
          _localAiMode = localAiModeRulesOnly;
          _localAiProvider = fallbackRulesProvider;
          _downloadProgress = null;
        });
        await _clearDownloadedModelSettings();
        if (!mounted) return;
        showInfoToast(context, 'Model record cleared.');
      } else {
        showErrorToast(context, 'Could not delete model: $error');
      }
    } finally {
      if (mounted) setState(() => _isDeletingModel = false);
    }
  }

  @override
  void dispose() {
    _huggingFaceTokenSyncTimer?.cancel();
    _localEndpointController.dispose();
    _localServerModelController.dispose();
    _cloudEndpointController.dispose();
    _cloudModelController.dispose();
    _cloudApiKeyController.dispose();
    _contextWindowController.dispose();
    _huggingFaceTokenController.dispose();
    super.dispose();
  }

  String _currentLocalAiStatus() {
    if (_localAiMode == localAiModeRulesOnly || !_useLocalAi) {
      return 'Deterministic rules only; no model is required.';
    }
    if (_localAiMode == localAiModeExternalServer) {
      return 'External local server will handle AI requests with ${_localServerModelController.text.trim().isEmpty ? defaultLocalAiModel : _localServerModelController.text.trim()}.';
    }
    if (_localAiMode == localAiModeExternalCloud) {
      final model = _cloudModelController.text.trim().isEmpty
          ? defaultCloudAiModel
          : _cloudModelController.text.trim();
      final keyStatus = _cloudApiKeyController.text.trim().isEmpty
          ? 'Add an API key before requests can run.'
          : 'API key saved locally on this device.';
      return '$_localAiProvider will handle AI requests with $model. $keyStatus';
    }
    if (_hasDownloadedModel) {
      return '${_downloadedModelName ?? 'On-device model'} is active for AI requests using $_localBackend backend.';
    }
    return 'On-device AI will activate after a public text model is installed; backend is set to $_localBackend.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF171B22), Color(0xFF0F1217)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            GlassPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tune the reading space',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Settings here are saved on this device. Rows marked planned are visible now but not wired into the rest of the app yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _StatChip(
                        icon: Icons.auto_awesome_rounded,
                        label: _enableMotionEffects
                            ? 'Motion enabled'
                            : 'Motion reduced',
                      ),
                      _StatChip(
                        icon: Icons.menu_book_rounded,
                        label: _immersiveReader
                            ? 'Immersive reader on'
                            : 'Reader chrome visible',
                      ),
                      _StatChip(
                        icon: Icons.image_rounded,
                        label:
                            'Image quality ${(100 * _imageQuality).round()}%',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Reader',
              subtitle: 'Small polish touches that shape the reading flow.',
              children: [
                _SwitchRow(
                  icon: Icons.chrome_reader_mode_rounded,
                  title: 'Immersive reader',
                  subtitle:
                      'Saved preference; reader chrome integration is planned.',
                  value: _immersiveReader,
                  onChanged: (value) {
                    setState(() => _immersiveReader = value);
                    _saveBool(LocalAiSettingsKeys.immersiveReader, value);
                    showInfoToast(
                      context,
                      value
                          ? 'Immersive reader preference saved.'
                          : 'Reader chrome preference saved.',
                    );
                  },
                ),
                _SwitchRow(
                  icon: Icons.animation_rounded,
                  title: 'Motion effects',
                  subtitle:
                      'Saved preference; app-wide motion handling is planned.',
                  value: _enableMotionEffects,
                  onChanged: (value) {
                    setState(() => _enableMotionEffects = value);
                    _saveBool(LocalAiSettingsKeys.enableMotionEffects, value);
                    showInfoToast(
                      context,
                      value
                          ? 'Motion preference saved.'
                          : 'Reduced-motion preference saved.',
                    );
                  },
                ),
                _SliderRow(
                  icon: Icons.hd_rounded,
                  title: 'Image quality',
                  subtitle:
                      'Saved preference; image request quality is not wired yet.',
                  value: _imageQuality,
                  onChanged: (value) => setState(() => _imageQuality = value),
                  onChangeEnd: (value) {
                    _saveDouble(LocalAiSettingsKeys.imageQuality, value);
                    showInfoToast(
                      context,
                      'Preferred image quality set to ${(100 * value).round()}%.',
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Downloads',
              subtitle: 'Prep for the offline flow we can build next.',
              children: [
                _SwitchRow(
                  icon: Icons.wifi_tethering_rounded,
                  title: 'Wi-Fi only downloads',
                  subtitle:
                      'Saved preference; network gating is not wired yet.',
                  value: _downloadOnWifiOnly,
                  onChanged: (value) {
                    setState(() => _downloadOnWifiOnly = value);
                    _saveBool(LocalAiSettingsKeys.downloadOnWifiOnly, value);
                    showInfoToast(
                      context,
                      value
                          ? 'Wi-Fi-only download preference saved.'
                          : 'Any-network download preference saved.',
                    );
                  },
                ),
                _ActionRow(
                  icon: Icons.delete_sweep_rounded,
                  title: 'Clear image cache',
                  subtitle: 'Remove cached covers and page previews.',
                  onTap: () {
                    imageCache.clear();
                    imageCache.clearLiveImages();
                    showInfoToast(context, 'Image cache cleared.');
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Content',
              subtitle: 'Guard rails for browsing extensions and feeds.',
              children: [
                _SwitchRow(
                  icon: Icons.visibility_off_rounded,
                  title: 'Hide explicit content',
                  subtitle:
                      'Exclude adult titles from imported recommendation feeds and AI searches.',
                  value: !_allowExplicitContent,
                  onChanged: (value) {
                    setState(() => _allowExplicitContent = !value);
                    _saveBool(LocalAiSettingsKeys.allowExplicitContent, !value);
                    showInfoToast(
                      context,
                      value
                          ? 'Explicit-content preference saved.'
                          : 'Explicit-content preference saved.',
                    );
                  },
                ),
                _ActionRow(
                  icon: Icons.tune_rounded,
                  title: 'Manage discover filters',
                  subtitle: 'Saved filters are not developed yet.',
                  onTap: () =>
                      showFeatureComingSoon(context, 'Discover filters'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Services',
              subtitle: 'Backend-backed service imports and account links.',
              children: [
                const _InfoRow(
                  icon: Icons.cloud_done_rounded,
                  title: 'Steam key location',
                  subtitle:
                      'The app now expects STEAM_WEB_API_KEY to live in Firebase Functions secrets, not in the frontend.',
                ),
                _ActionRow(
                  icon: Icons.person_rounded,
                  title: 'Manage profile links',
                  subtitle:
                      'Open Profile to sign in and save a public Steam profile identifier.',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Local AI',
              subtitle:
                  'Model controls for local-only profile summaries and search interpretation.',
              children: [
                _OptionRow(
                  icon: Icons.route_rounded,
                  title: 'AI mode',
                  subtitle: 'Choose how Majika handles local reasoning.',
                  value: _localAiMode,
                  options: _localAiModeOptions,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _localAiMode = value;
                      _useLocalAi = value != localAiModeRulesOnly;
                      _localAiProvider = switch (value) {
                        localAiModeOnDevice => _selectedModel.providerLabel,
                        localAiModeExternalCloud =>
                          _effectiveCloudProviderPreset.provider,
                        localAiModeManual => localAiModeManual,
                        _ => value,
                      };
                    });
                    _saveString(LocalAiSettingsKeys.localAiMode, value);
                    _saveString(
                      LocalAiSettingsKeys.localAiProvider,
                      value == localAiModeExternalCloud
                          ? externalCloudAiProvider
                          : _localAiProvider,
                    );
                    if (value == localAiModeExternalCloud) {
                      _saveString(
                        LocalAiSettingsKeys.cloudAiProvider,
                        _localAiProvider,
                      );
                    }
                    _saveBool(
                      LocalAiSettingsKeys.useLocalAi,
                      value != localAiModeRulesOnly,
                    );
                    showInfoToast(context, 'Local AI mode set to $value.');
                  },
                ),
                if (_supportsOnDeviceAi &&
                    (_usesOnDeviceAi || _hasDownloadedModel))
                  _ModelDownloadCard(
                    models: _visibleLocalAiModels,
                    selectedModel: _effectiveSelectedModel,
                    isDownloading: _isDownloadingModel,
                    isDeleting: _isDeletingModel,
                    progress: _downloadProgress,
                    downloadedId: _downloadedModelId,
                    downloadedName: _downloadedModelName,
                    onModelSelected: (model) {
                      setState(() {
                        _selectedModel = model;
                        _localAiProvider = model.providerLabel;
                        _localAiMode = localAiModeOnDevice;
                        _useLocalAi = true;
                      });
                      _saveString(
                        LocalAiSettingsKeys.selectedModelId,
                        model.id,
                      );
                      _saveString(
                        LocalAiSettingsKeys.selectedModelName,
                        model.name,
                      );
                      _saveString(
                        LocalAiSettingsKeys.localAiMode,
                        localAiModeOnDevice,
                      );
                      _saveString(
                        LocalAiSettingsKeys.localAiProvider,
                        model.providerLabel,
                      );
                    },
                    huggingFaceTokenController: _huggingFaceTokenController,
                    onHuggingFaceTokenChanged: _saveHuggingFaceToken,
                    onDownload: _downloadRecommendedModel,
                    onCancel: _cancelModelDownload,
                    onDelete: _deleteDownloadedModel,
                  ),
                if (_usesOnDeviceAi && _supportsOnDeviceAi)
                  _OptionRow(
                    icon: Icons.speed_rounded,
                    title: 'On-device backend',
                    subtitle:
                        'Auto lets LiteRT choose; CPU is safest, GPU/NPU can be faster on newer devices.',
                    value: _localBackend,
                    options: const [
                      localAiBackendAuto,
                      localAiBackendCpu,
                      localAiBackendGpu,
                      localAiBackendNpu,
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _localBackend = value);
                      _saveString(LocalAiSettingsKeys.localBackend, value);
                      showInfoToast(context, 'Local AI backend set to $value.');
                    },
                  ),
                if (_usesOnDeviceAi && _supportsOnDeviceAi)
                  _SwitchRow(
                    icon: Icons.tune_rounded,
                    title: 'Advanced model choice',
                    subtitle: 'Show custom import controls.',
                    value: _showAdvancedLocalAi,
                    onChanged: (value) =>
                        setState(() => _showAdvancedLocalAi = value),
                  ),
                if (_usesOnDeviceAi &&
                    _supportsOnDeviceAi &&
                    _showAdvancedLocalAi)
                  _ActionRow(
                    icon: Icons.file_open_rounded,
                    title: 'Import custom model file',
                    subtitle:
                        'Advanced: bring a downloaded .litertlm or .task file from Hugging Face.',
                    onTap: () =>
                        showFeatureComingSoon(context, 'Custom model import'),
                  ),
                if (_usesExternalServer)
                  _TextFieldRow(
                    fieldKey: const ValueKey('local-ai-endpoint'),
                    icon: Icons.dns_rounded,
                    title: 'Local server endpoint',
                    subtitle:
                        'OpenAI-compatible /v1/chat/completions endpoint.',
                    controller: _localEndpointController,
                    hintText: defaultLocalAiEndpoint,
                    onChanged: (value) =>
                        _saveString(LocalAiSettingsKeys.localEndpoint, value),
                  ),
                if (_usesExternalServer)
                  _ServerModelPresetCard(
                    presets: _serverModelPresets,
                    selectedPreset: _effectiveServerModelPreset,
                    installedOllamaModels: _installedOllamaModels,
                    isLoadingInstalledModels: _isLoadingServerModels,
                    statusMessage: _serverModelStatusMessage,
                    onRefreshInstalledModels: _refreshServerModels,
                    onPresetSelected: (preset) {
                      final value = preset.name;
                      setState(() {
                        _localServerModelController.text = value;
                        _localEndpointController.text = preset.runtime.endpoint;
                      });
                      _saveString(
                        LocalAiSettingsKeys.localEndpoint,
                        preset.runtime.endpoint,
                      );
                      _saveString(LocalAiSettingsKeys.localServerModel, value);
                      showInfoToast(
                        context,
                        'Local server model set to $value.',
                      );
                    },
                  ),
                if (_usesExternalServer)
                  _TextFieldRow(
                    fieldKey: const ValueKey('local-ai-server-model'),
                    icon: Icons.smart_toy_rounded,
                    title: 'Local server model',
                    subtitle:
                        'Model name sent in OpenAI-compatible requests, such as gemma3:4b.',
                    controller: _localServerModelController,
                    hintText: defaultLocalAiModel,
                    onChanged: (value) {
                      setState(() {});
                      _saveString(LocalAiSettingsKeys.localServerModel, value);
                    },
                  ),
                if (_usesExternalServer)
                  _ServerRuntimeHelpCard(
                    ollamaCommand: _ollamaServeCommand,
                    ollamaPullCommand: _ollamaPullCommand,
                    flmCommand: _flmServeCommand,
                    flmPullCommand: _flmPullCommand,
                    onUseOllama: () {
                      unawaited(_useOllamaDefaults());
                      showInfoToast(context, 'Ollama endpoint selected.');
                    },
                    onUseFlm: () {
                      unawaited(_useFlmDefaults());
                      showInfoToast(context, 'FastFlowLM endpoint selected.');
                    },
                    onRefresh: _refreshServerModels,
                    onCopyOllama: () =>
                        _copyServerCommand('Ollama', _ollamaServeCommand),
                    onCopyOllamaPull: () =>
                        _copyServerCommand('Ollama pull', _ollamaPullCommand),
                    onCopyFlm: () =>
                        _copyServerCommand('FastFlowLM', _flmServeCommand),
                    onCopyFlmPull: () =>
                        _copyServerCommand('FastFlowLM pull', _flmPullCommand),
                  ),
                if (_usesExternalCloud)
                  _CloudAiProviderCard(
                    presets: _externalCloudAiPresets,
                    selectedPreset: _effectiveCloudProviderPreset,
                    onPresetSelected: (preset) {
                      unawaited(_useCloudProvider(preset));
                      showInfoToast(
                        context,
                        '${preset.provider} cloud AI selected.',
                      );
                    },
                  ),
                if (_usesExternalCloud)
                  _TextFieldRow(
                    fieldKey: const ValueKey('cloud-ai-api-key'),
                    icon: Icons.key_rounded,
                    title: 'Cloud API key',
                    subtitle:
                        'Each user should paste their own key. Majika saves it locally on this device.',
                    controller: _cloudApiKeyController,
                    hintText: 'Paste provider API key',
                    obscureText: true,
                    onChanged: (value) => _saveString(
                      LocalAiSettingsKeys.cloudApiKey,
                      value.trim(),
                    ),
                  ),
                if (_usesExternalCloud)
                  _TextFieldRow(
                    fieldKey: const ValueKey('cloud-ai-endpoint'),
                    icon: Icons.cloud_queue_rounded,
                    title: 'Cloud endpoint',
                    subtitle:
                        'OpenAI-compatible /chat/completions endpoint for the selected provider.',
                    controller: _cloudEndpointController,
                    hintText: _effectiveCloudProviderPreset.endpoint,
                    onChanged: (value) =>
                        _saveString(LocalAiSettingsKeys.cloudEndpoint, value),
                  ),
                if (_usesExternalCloud)
                  _TextFieldRow(
                    fieldKey: const ValueKey('cloud-ai-model'),
                    icon: Icons.smart_toy_rounded,
                    title: 'Cloud model',
                    subtitle:
                        'For OpenRouter free usage, use a model ID ending in :free.',
                    controller: _cloudModelController,
                    hintText: _effectiveCloudProviderPreset.model,
                    onChanged: (value) {
                      setState(() {});
                      _saveString(LocalAiSettingsKeys.cloudModel, value);
                    },
                  ),
                if (_usesExternalCloud)
                  const _InfoRow(
                    icon: Icons.privacy_tip_rounded,
                    title: 'Cloud privacy note',
                    subtitle:
                        'Recommendation prompts and taste-profile signals are sent to the selected provider. Use rules-only or on-device AI to keep AI reasoning local.',
                  ),
                if (_localAiMode == localAiModeManual)
                  const _InfoRow(
                    icon: Icons.content_paste_go_rounded,
                    title: 'Manual AI prompt handoff',
                    subtitle:
                        'Majika will show each AI prompt for copying. Paste it into ChatGPT or another AI, then paste that response back into Majika.',
                  ),
                _SwitchRow(
                  icon: Icons.manage_search_rounded,
                  title: 'AI search interpretation',
                  subtitle:
                      'Saved preference; falls back to deterministic parsing without a local model.',
                  value: _useAiForSearch,
                  onChanged: (value) {
                    setState(() => _useAiForSearch = value);
                    _saveBool(LocalAiSettingsKeys.useAiForSearch, value);
                    showInfoToast(
                      context,
                      value
                          ? 'Search interpretation enabled.'
                          : 'Search will use fallback rules only.',
                    );
                  },
                ),
                _TextFieldRow(
                  fieldKey: const ValueKey('ai-context-window-tokens'),
                  icon: Icons.dataset_rounded,
                  title: 'AI context window override',
                  subtitle:
                      'Optional token limit for custom models. Leave blank to use Majika’s conservative model-specific limit.',
                  controller: _contextWindowController,
                  hintText: _resolvedContextWindowTokens.toString(),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {});
                    _saveContextWindowOverride(value);
                  },
                ),
                _InfoRow(
                  icon: Icons.data_usage_rounded,
                  title: 'Resolved AI context window',
                  subtitle:
                      '${formatAiTokenCount(_resolvedContextWindowTokens)} tokens. Majika reserves response and safety space, then packs the highest-value evidence that fits.',
                ),
                _InfoRow(
                  icon: Icons.offline_bolt_rounded,
                  title: 'Current AI path',
                  subtitle: _currentLocalAiStatus(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'About',
              subtitle: 'Status of the current prototype.',
              children: const [
                _InfoRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Majika',
                  subtitle: 'Prototype build 1.0.0+1',
                ),
                _InfoRow(
                  icon: Icons.extension_rounded,
                  title: 'Discover source',
                  subtitle: 'Typed AniList connector',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => showFeatureComingSoon(
                context,
                'Cloud sync and account settings',
              ),
              icon: Icon(Icons.cloud_sync_outlined, color: accent),
              label: Text(
                'Cloud sync is coming later',
                style: theme.textTheme.bodyMedium?.copyWith(color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DownloadableModel {
  final String id;
  final String name;
  final String sizeLabel;
  final String providerLabel;
  final _AiModelTier tier;
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

  const _DownloadableModel({
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

  String get platformNote {
    if (supportsCurrentPlatform) return description;
    return '$description This model is not available for this platform.';
  }
}

class _ServerModelPreset {
  final String name;
  final _ServerRuntime runtime;
  final _AiModelTier tier;
  final String sizeLabel;
  final String description;

  const _ServerModelPreset({
    required this.name,
    required this.runtime,
    required this.tier,
    required this.sizeLabel,
    required this.description,
  });

  String get downloadCommand => switch (runtime) {
    _ServerRuntime.ollama => 'ollama pull $name',
    _ServerRuntime.fastFlowLm => 'flm pull $name',
  };

  String get serveCommand => switch (runtime) {
    _ServerRuntime.ollama => 'ollama run $name',
    _ServerRuntime.fastFlowLm => 'flm serve $name',
  };

  @override
  bool operator ==(Object other) {
    return other is _ServerModelPreset &&
        other.name == name &&
        other.runtime == runtime;
  }

  @override
  int get hashCode => Object.hash(name, runtime);
}

class _CloudAiProviderPreset {
  final String provider;
  final String endpoint;
  final String model;
  final _AiModelTier tier;
  final String freeLabel;
  final String keyUrl;
  final String description;

  const _CloudAiProviderPreset({
    required this.provider,
    required this.endpoint,
    required this.model,
    required this.tier,
    required this.freeLabel,
    required this.keyUrl,
    required this.description,
  });
}

class _HuggingFaceTokenRequiredException implements Exception {
  const _HuggingFaceTokenRequiredException();
}

String _downloadModelErrorMessage(Object error, _DownloadableModel model) {
  if (error is _HuggingFaceTokenRequiredException) {
    return 'Add a Hugging Face read token before downloading ${model.name}.';
  }

  final normalizedError = error.toString().toLowerCase();
  final looksLikeHuggingFaceAccessError =
      model.needsHuggingFaceToken &&
      (normalizedError.contains('http 403') ||
          normalizedError.contains('access forbidden') ||
          normalizedError.contains('does not have access') ||
          normalizedError.contains('for gated models'));

  if (looksLikeHuggingFaceAccessError) {
    return 'Hugging Face blocked ${model.name}. Open Access model, accept or request access with the same account as your token, then retry.';
  }

  return 'Could not download ${model.name}: $error';
}

bool _looksLikeOllamaEndpoint(String endpoint) {
  final uri = Uri.tryParse(endpoint);
  if (uri == null) return true;
  if (uri.port == 52625) return false;
  if (uri.path.contains('/v1') || uri.path.contains('/chat/completions')) {
    return uri.port == 11434;
  }
  return endpoint.contains('11434') || !endpoint.contains('52625');
}

bool _looksLikeEmbeddingModel(String modelName) {
  final normalized = modelName.toLowerCase();
  return normalized.contains('embed') || normalized.contains('nomic-embed');
}

Uri _ollamaTagsUri(String endpoint) {
  final uri = Uri.parse(endpoint);
  var path = uri.path;
  for (final suffix in ['/v1/chat/completions', '/chat/completions', '/v1']) {
    if (path.endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      break;
    }
  }
  return uri.replace(path: '$path/api/tags', query: '');
}

class _CloudAiProviderCard extends StatelessWidget {
  final List<_CloudAiProviderPreset> presets;
  final _CloudAiProviderPreset selectedPreset;
  final ValueChanged<_CloudAiProviderPreset> onPresetSelected;

  const _CloudAiProviderCard({
    required this.presets,
    required this.selectedPreset,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_done_rounded,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud AI provider',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bring your own free-tier API key.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonHideUnderline(
            child: DropdownButton<_CloudAiProviderPreset>(
              value: selectedPreset,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1F27),
              iconEnabledColor: Colors.white70,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              items: [
                for (final preset in presets)
                  DropdownMenuItem(
                    value: preset,
                    child: Text(
                      '${preset.provider} · ${preset.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (preset) {
                if (preset != null) onPresetSelected(preset);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${selectedPreset.freeLabel} · ${selectedPreset.tier.label}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            selectedPreset.description,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _openCloudProviderKeys(selectedPreset),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Get API key'),
          ),
        ],
      ),
    );
  }
}

class _ServerModelPresetCard extends StatelessWidget {
  final List<_ServerModelPreset> presets;
  final _ServerModelPreset selectedPreset;
  final Set<String> installedOllamaModels;
  final bool isLoadingInstalledModels;
  final String? statusMessage;
  final Future<void> Function() onRefreshInstalledModels;
  final ValueChanged<_ServerModelPreset> onPresetSelected;

  const _ServerModelPresetCard({
    required this.presets,
    required this.selectedPreset,
    required this.installedOllamaModels,
    required this.isLoadingInstalledModels,
    required this.statusMessage,
    required this.onRefreshInstalledModels,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedInstalled = _isPresetInstalled(selectedPreset);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  selectedPreset.tier.icon,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server model catalog',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Installed Ollama models plus Majika-friendly downloads.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh installed models',
                onPressed: isLoadingInstalledModels
                    ? null
                    : () => unawaited(onRefreshInstalledModels()),
                icon: isLoadingInstalledModels
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonHideUnderline(
            child: DropdownButton<_ServerModelPreset>(
              value: selectedPreset,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1F27),
              iconEnabledColor: Colors.white70,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              items: [
                for (final preset in presets)
                  DropdownMenuItem(
                    value: preset,
                    child: _ServerModelMenuItem(
                      preset: preset,
                      isInstalled: _isPresetInstalled(preset),
                    ),
                  ),
              ],
              onChanged: (preset) {
                if (preset != null) onPresetSelected(preset);
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ModelStatusChip(
                icon: selectedInstalled
                    ? Icons.check_circle_rounded
                    : Icons.download_rounded,
                label: selectedInstalled ? 'Installed' : 'Needs download',
                color: selectedInstalled
                    ? Colors.greenAccent
                    : Colors.white.withValues(alpha: 0.62),
              ),
              _ModelStatusChip(
                icon: selectedPreset.runtime.icon,
                label: selectedPreset.runtime.label,
                color: theme.colorScheme.secondary,
              ),
              _ModelStatusChip(
                icon: selectedPreset.tier.icon,
                label:
                    '${selectedPreset.sizeLabel} · ${selectedPreset.tier.label}',
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selectedPreset.description,
            style: TextStyle(
              color: selectedInstalled ? Colors.white70 : Colors.white60,
              height: 1.35,
            ),
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              statusMessage!,
              style: const TextStyle(color: Colors.white54, height: 1.3),
            ),
          ],
          const SizedBox(height: 10),
          SelectableText(
            selectedInstalled
                ? selectedPreset.serveCommand
                : selectedPreset.downloadCommand,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: selectedPreset.runtime == _ServerRuntime.ollama
                ? _openOllamaDownload
                : _openFastFlowLmDownload,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text('Install ${selectedPreset.runtime.label}'),
          ),
        ],
      ),
    );
  }

  bool _isPresetInstalled(_ServerModelPreset preset) {
    if (preset.runtime == _ServerRuntime.fastFlowLm) return false;
    return installedOllamaModels.contains(preset.name);
  }
}

class _ServerModelMenuItem extends StatelessWidget {
  final _ServerModelPreset preset;
  final bool isInstalled;

  const _ServerModelMenuItem({required this.preset, required this.isInstalled});

  @override
  Widget build(BuildContext context) {
    final color = isInstalled ? Colors.white : Colors.white54;
    return Row(
      children: [
        Icon(
          isInstalled ? Icons.check_circle_rounded : Icons.download_rounded,
          size: 16,
          color: isInstalled ? Colors.greenAccent : Colors.white54,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${preset.runtime.label} · ${preset.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

class _ModelStatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ModelStatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerRuntimeHelpCard extends StatelessWidget {
  final String ollamaCommand;
  final String ollamaPullCommand;
  final String flmCommand;
  final String flmPullCommand;
  final VoidCallback onUseOllama;
  final VoidCallback onUseFlm;
  final VoidCallback onRefresh;
  final VoidCallback onCopyOllama;
  final VoidCallback onCopyOllamaPull;
  final VoidCallback onCopyFlm;
  final VoidCallback onCopyFlmPull;

  const _ServerRuntimeHelpCard({
    required this.ollamaCommand,
    required this.ollamaPullCommand,
    required this.flmCommand,
    required this.flmPullCommand,
    required this.onUseOllama,
    required this.onUseFlm,
    required this.onRefresh,
    required this.onCopyOllama,
    required this.onCopyOllamaPull,
    required this.onCopyFlm,
    required this.onCopyFlmPull,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Serve a local model',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a runtime, copy its start command, then leave it running while Majika searches.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _ServerCommandRow(
            title: 'Ollama',
            subtitle:
                'Endpoint $defaultLocalAiEndpoint; refresh reads /api/tags from this device.',
            command: ollamaCommand,
            secondaryCommand: ollamaPullCommand,
            onUse: onUseOllama,
            onCopy: onCopyOllama,
            onCopySecondary: onCopyOllamaPull,
          ),
          const SizedBox(height: 10),
          _ServerCommandRow(
            title: 'FastFlowLM',
            subtitle:
                'Endpoint $_flmLocalAiEndpoint; use flm list on supported Windows Ryzen AI devices.',
            command: flmCommand,
            secondaryCommand: flmPullCommand,
            onUse: onUseFlm,
            onCopy: onCopyFlm,
            onCopySecondary: onCopyFlmPull,
          ),
        ],
      ),
    );
  }
}

class _ServerCommandRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String command;
  final String secondaryCommand;
  final VoidCallback onUse;
  final VoidCallback onCopy;
  final VoidCallback onCopySecondary;

  const _ServerCommandRow({
    required this.title,
    required this.subtitle,
    required this.command,
    required this.secondaryCommand,
    required this.onUse,
    required this.onCopy,
    required this.onCopySecondary,
  });

  @override
  Widget build(BuildContext context) {
    final actionButtons = Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        IconButton.filledTonal(
          tooltip: 'Use $title settings',
          onPressed: onUse,
          icon: const Icon(Icons.check_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Copy $title command',
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Copy $title download command',
          onPressed: onCopySecondary,
          icon: const Icon(Icons.download_rounded),
        ),
      ],
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, height: 1.3),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 260) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionButtons,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 8),
                  Flexible(child: actionButtons),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              command,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              secondaryCommand,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelDownloadCard extends StatelessWidget {
  final List<_DownloadableModel> models;
  final _DownloadableModel selectedModel;
  final bool isDownloading;
  final bool isDeleting;
  final double? progress;
  final String? downloadedId;
  final String? downloadedName;
  final ValueChanged<_DownloadableModel> onModelSelected;
  final TextEditingController huggingFaceTokenController;
  final ValueChanged<String> onHuggingFaceTokenChanged;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _ModelDownloadCard({
    required this.models,
    required this.selectedModel,
    required this.isDownloading,
    required this.isDeleting,
    required this.progress,
    required this.downloadedId,
    required this.downloadedName,
    required this.onModelSelected,
    required this.huggingFaceTokenController,
    required this.onHuggingFaceTokenChanged,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloaded =
        downloadedId == selectedModel.id ||
        downloadedName == selectedModel.name;
    Widget modelIcon() {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.download_for_offline_rounded,
          color: theme.colorScheme.secondary,
        ),
      );
    }

    Widget modelDetails() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<_DownloadableModel>(
              value: selectedModel,
              isExpanded: true,
              padding: EdgeInsets.zero,
              dropdownColor: const Color(0xFF1A1F27),
              iconEnabledColor: Colors.white70,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              items: [
                for (final model in models)
                  DropdownMenuItem(
                    value: model,
                    child: Text(
                      model.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: isDownloading
                  ? null
                  : (model) {
                      if (model != null) onModelSelected(model);
                    },
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${selectedModel.sizeLabel} · ${selectedModel.tier.label} · ${selectedModel.resourceLabel}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      );
    }

    Widget downloadButton() {
      return FilledButton.icon(
        key: const ValueKey('download-recommended-ai-model'),
        onPressed: isDeleting ? null : (isDownloading ? onCancel : onDownload),
        icon: isDownloading
            ? const Icon(Icons.cancel_rounded)
            : Icon(
                isDownloaded
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
              ),
        label: Text(
          isDownloading ? 'Cancel' : (isDownloaded ? 'Downloaded' : 'Download'),
        ),
      );
    }

    Widget deleteButton() {
      return IconButton.filledTonal(
        key: const ValueKey('delete-downloaded-ai-model'),
        tooltip: 'Delete downloaded model',
        onPressed: isDownloading || isDeleting ? null : onDelete,
        icon: isDeleting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_rounded),
      );
    }

    Widget modelActions() {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: [if (isDownloaded) deleteButton(), downloadButton()],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 390) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        modelIcon(),
                        const SizedBox(width: 12),
                        Expanded(child: modelDetails()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: modelActions(),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  modelIcon(),
                  const SizedBox(width: 12),
                  Expanded(child: modelDetails()),
                  const SizedBox(width: 12),
                  modelActions(),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            selectedModel.description,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          if (selectedModel.needsHuggingFaceToken) ...[
            const SizedBox(height: 12),
            _HuggingFaceTokenPanel(
              model: selectedModel,
              controller: huggingFaceTokenController,
              onChanged: onHuggingFaceTokenChanged,
            ),
          ],
          if (isDownloading || progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _HuggingFaceTokenPanel extends StatelessWidget {
  final _DownloadableModel model;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _HuggingFaceTokenPanel({
    required this.model,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.key_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hugging Face token',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: const ValueKey('hugging-face-access-model'),
                onPressed: () => _openHuggingFaceModelAccess(model),
                icon: const Icon(Icons.fact_check_rounded, size: 16),
                label: const Text('Access model'),
              ),
              TextButton.icon(
                onPressed: _openHuggingFaceTokens,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Tokens'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('hugging-face-token'),
            controller: controller,
            obscureText: true,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'hf_...',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Before downloading ${model.name}, open Access model while signed into Hugging Face, accept or request the model license, then paste a read token from that same account. Majika saves it locally and also adds it to your profile if you are signed in.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openHuggingFaceModelAccess(_DownloadableModel model) async {
  final uri = Uri.parse(model.accessPageUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openHuggingFaceTokens() async {
  final uri = Uri.parse('https://huggingface.co/settings/tokens');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openCloudProviderKeys(_CloudAiProviderPreset preset) async {
  final uri = Uri.parse(preset.keyUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openOllamaDownload() async {
  final uri = Uri.parse('https://ollama.com/download');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openFastFlowLmDownload() async {
  final uri = Uri.parse('https://fastflowlm.com/');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: Colors.white70),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                subtitle,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            dropdownColor: const Color(0xFF1A1F27),
            iconEnabledColor: Colors.white70,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(context),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option,
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _TextFieldRow extends StatelessWidget {
  final Key? fieldKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _TextFieldRow({
    this.fieldKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: Colors.white70),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                subtitle,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          TextField(
            key: fieldKey,
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(context).copyWith(hintText: hintText),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: Colors.white70),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                subtitle,
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Text(
                '${(100 * value).round()}%',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          Slider(value: value, onChanged: onChanged, onChangeEnd: onChangeEnd),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white54,
        ),
        onTap: onTap,
      ),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context) {
  final accent = Theme.of(context).colorScheme.secondary;

  return InputDecoration(
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    hintStyle: const TextStyle(color: Colors.white38),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: accent.withValues(alpha: 0.8)),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }
}
