import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/ui/profile/profile_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:majika/ui/shared/glass_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _downloadableLocalAiModels = [
  _DownloadableModel(
    id: 'gemma3_1b_it',
    name: 'Gemma 3 1B IT',
    sizeLabel: '586 MB',
    providerLabel: 'Gemma',
    resourceLabel: 'Small Google text model',
    mobileUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    description:
        'Best current default for this SDK: compact enough for newer phones while staying stronger than tiny fallback models.',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
  ),
  _DownloadableModel(
    id: 'gemma3n_e2b_it',
    name: 'Gemma 3n E2B IT',
    sizeLabel: '3.1 GB',
    providerLabel: 'Gemma',
    resourceLabel: 'Advanced Google multimodal model',
    mobileUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm',
    description:
        'Higher-capability Google model for newer devices with enough memory.',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    isAdvanced: true,
  ),
  _DownloadableModel(
    id: 'gemma3n_e4b_it',
    name: 'Gemma 3n E4B IT',
    sizeLabel: '6.5 GB',
    providerLabel: 'Gemma',
    resourceLabel: 'Large Google multimodal model',
    mobileUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4.litertlm',
    description:
        'Large model option for powerful devices; benchmark before making it your daily default.',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    isAdvanced: true,
  ),
  _DownloadableModel(
    id: 'qwen3_0_6b',
    name: 'Qwen3 0.6B',
    sizeLabel: '586 MB',
    providerLabel: 'Qwen',
    resourceLabel: 'Balanced public text model',
    mobileUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    description:
        'Small public alternative that is useful when Gemma model access is not available.',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    isAdvanced: true,
  ),
  _DownloadableModel(
    id: 'deepseek_r1_qwen_1_5b',
    name: 'DeepSeek R1 Distill Qwen 1.5B',
    sizeLabel: '1.7 GB',
    providerLabel: 'DeepSeek',
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
  ),
  _DownloadableModel(
    id: 'qwen25_1_5b_instruct',
    name: 'Qwen 2.5 1.5B Instruct',
    sizeLabel: '1.6 GB',
    providerLabel: 'Qwen',
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
  ),
];

final _defaultLocalAiModel = _downloadableLocalAiModels.first;
const _externalLocalServerModelPresets = [
  'gemma3:270m',
  'gemma3:1b',
  'gemma3:4b',
  'gemma3:12b',
  'gemma3:27b',
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
  bool _showAdvancedLocalAi = false;
  String _localAiMode = localAiModeRulesOnly;
  String _localBackend = localAiBackendAuto;
  String _localAiProvider = _defaultLocalAiModel.providerLabel;
  _DownloadableModel _selectedModel = _defaultLocalAiModel;
  String? _downloadedModelId;
  String? _downloadedModelName;
  double _imageQuality = 0.85;
  double _aiContextItems = 24;
  double? _downloadProgress;
  final _localEndpointController = TextEditingController(
    text: defaultLocalAiEndpoint,
  );
  final _localServerModelController = TextEditingController(
    text: defaultLocalAiModel,
  );

  bool get _hasDownloadedModel =>
      _downloadedModelId != null || _downloadedModelName != null;

  bool get _usesOnDeviceAi => _localAiMode == localAiModeOnDevice;

  bool get _usesExternalServer => _localAiMode == localAiModeExternalServer;

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
          (savedMode == localAiModeOnDevice ||
              savedMode == localAiModeExternalServer);
      _useAiForSearch =
          prefs.getBool(LocalAiSettingsKeys.useAiForSearch) ?? _useAiForSearch;
      _localAiMode = savedMode;
      _localBackend =
          prefs.getString(LocalAiSettingsKeys.localBackend) ??
          localAiBackendAuto;
      if (_localAiMode == localAiModeRulesOnly) {
        _useLocalAi = false;
      }
      _localAiProvider =
          legacyProvider ?? selectedModel?.providerLabel ?? _localAiProvider;
      _selectedModel = selectedModel ?? _selectedModel;
      _downloadedModelId = prefs.getString(
        LocalAiSettingsKeys.downloadedModelId,
      );
      _downloadedModelName = prefs.getString(
        LocalAiSettingsKeys.downloadedModelName,
      );
      _imageQuality =
          prefs.getDouble(LocalAiSettingsKeys.imageQuality) ?? _imageQuality;
      _aiContextItems =
          prefs.getDouble(LocalAiSettingsKeys.aiContextItems) ??
          _aiContextItems;
      _localEndpointController.text =
          prefs.getString(LocalAiSettingsKeys.localEndpoint) ??
          _localEndpointController.text;
      _localServerModelController.text =
          prefs.getString(LocalAiSettingsKeys.localServerModel) ??
          _localServerModelController.text;
    });
  }

  String _modeFromLegacyProvider(String? provider) {
    return switch (provider) {
      externalLocalAiProvider => localAiModeExternalServer,
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

  Future<void> _downloadRecommendedModel() async {
    if (_isDownloadingModel) return;

    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = null;
    });

    try {
      await FlutterGemma.initialize();
      final modelToDownload = _effectiveSelectedModel;
      final installation =
          await FlutterGemma.installModel(
            modelType: modelToDownload.modelType,
            fileType: modelToDownload.fileType,
          ).fromNetwork(modelToDownload.url).withProgress((progress) {
            if (mounted) setState(() => _downloadProgress = progress / 100);
          }).install();

      if (!mounted) return;
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
      showErrorToast(context, 'Could not download model: $error');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingModel = false);
      }
    }
  }

  @override
  void dispose() {
    _localEndpointController.dispose();
    _localServerModelController.dispose();
    super.dispose();
  }

  String _currentLocalAiStatus() {
    if (_localAiMode == localAiModeRulesOnly || !_useLocalAi) {
      return 'Deterministic rules only; no model is required.';
    }
    if (_localAiMode == localAiModeExternalServer) {
      return 'External local server will handle AI requests.';
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
                      'Saved preference; feed filtering is not wired yet.',
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
                  options: const [
                    localAiModeOnDevice,
                    localAiModeExternalServer,
                    localAiModeRulesOnly,
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _localAiMode = value;
                      _useLocalAi = value != localAiModeRulesOnly;
                      _localAiProvider = value == localAiModeOnDevice
                          ? _selectedModel.providerLabel
                          : value;
                    });
                    _saveString(LocalAiSettingsKeys.localAiMode, value);
                    _saveString(
                      LocalAiSettingsKeys.localAiProvider,
                      value == localAiModeOnDevice
                          ? _selectedModel.providerLabel
                          : value,
                    );
                    _saveBool(
                      LocalAiSettingsKeys.useLocalAi,
                      value != localAiModeRulesOnly,
                    );
                    showInfoToast(context, 'Local AI mode set to $value.');
                  },
                ),
                if (_usesOnDeviceAi)
                  _ModelDownloadCard(
                    models: _visibleLocalAiModels,
                    selectedModel: _effectiveSelectedModel,
                    isDownloading: _isDownloadingModel,
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
                    onDownload: _downloadRecommendedModel,
                  ),
                if (_usesOnDeviceAi)
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
                if (_usesOnDeviceAi)
                  _SwitchRow(
                    icon: Icons.tune_rounded,
                    title: 'Advanced model choice',
                    subtitle: 'Show custom import controls.',
                    value: _showAdvancedLocalAi,
                    onChanged: (value) =>
                        setState(() => _showAdvancedLocalAi = value),
                  ),
                if (_usesOnDeviceAi && _showAdvancedLocalAi)
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
                  _OptionRow(
                    icon: Icons.memory_rounded,
                    title: 'Server model preset',
                    subtitle:
                        'Common Ollama model names; edit the field below for LM Studio or custom names.',
                    value:
                        _externalLocalServerModelPresets.contains(
                          _localServerModelController.text,
                        )
                        ? _localServerModelController.text
                        : defaultLocalAiModel,
                    options: _externalLocalServerModelPresets,
                    onChanged: (value) {
                      if (value == null) return;
                      _localServerModelController.text = value;
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
                    onChanged: (value) => _saveString(
                      LocalAiSettingsKeys.localServerModel,
                      value,
                    ),
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
                _SliderRow(
                  icon: Icons.dataset_rounded,
                  title: 'Recommendation context items',
                  subtitle:
                      'How many profile and candidate signals to pass to the local model.',
                  value: _aiContextItems,
                  min: 8,
                  max: 48,
                  divisions: 5,
                  label: _aiContextItems.round().toString(),
                  valueText: _aiContextItems.round().toString(),
                  onChanged: (value) => setState(() => _aiContextItems = value),
                  onChangeEnd: (value) {
                    _saveDouble(LocalAiSettingsKeys.aiContextItems, value);
                    showInfoToast(
                      context,
                      'Local AI context limit set to ${value.round()} items.',
                    );
                  },
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
  final String resourceLabel;
  final String mobileUrl;
  final String? desktopUrl;
  final String description;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool isAdvanced;

  const _DownloadableModel({
    required this.id,
    required this.name,
    required this.sizeLabel,
    required this.providerLabel,
    required this.resourceLabel,
    required this.mobileUrl,
    this.desktopUrl,
    required this.description,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.isAdvanced = false,
  });

  String get url {
    final desktop = desktopUrl;
    if (isDesktop && desktop != null) return desktop;
    return mobileUrl;
  }

  bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  bool get supportsCurrentPlatform {
    if (isDesktop) return desktopUrl != null;
    return mobileUrl.isNotEmpty;
  }

  String get platformNote {
    if (supportsCurrentPlatform) return description;
    return '$description This model is not available for this platform.';
  }
}

class _ModelDownloadCard extends StatelessWidget {
  final List<_DownloadableModel> models;
  final _DownloadableModel selectedModel;
  final bool isDownloading;
  final double? progress;
  final String? downloadedId;
  final String? downloadedName;
  final ValueChanged<_DownloadableModel> onModelSelected;
  final VoidCallback onDownload;

  const _ModelDownloadCard({
    required this.models,
    required this.selectedModel,
    required this.isDownloading,
    required this.progress,
    required this.downloadedId,
    required this.downloadedName,
    required this.onModelSelected,
    required this.onDownload,
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
            '${selectedModel.sizeLabel} · ${selectedModel.resourceLabel}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      );
    }

    Widget downloadButton() {
      return FilledButton.icon(
        key: const ValueKey('download-recommended-ai-model'),
        onPressed: isDownloading ? null : onDownload,
        icon: isDownloading
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isDownloaded
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
              ),
        label: Text(isDownloaded ? 'Downloaded' : 'Download'),
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
                      child: downloadButton(),
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
                  downloadButton(),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            selectedModel.description,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
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
  final ValueChanged<String>? onChanged;

  const _TextFieldRow({
    this.fieldKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.hintText,
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
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final String? valueText;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.valueText,
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
                valueText ?? '${(100 * value).round()}%',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
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
