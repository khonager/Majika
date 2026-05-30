import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:majika/ui/shared/glass_panel.dart';

const _downloadableLocalAiModels = [
  _DownloadableModel(
    name: 'FunctionGemma 270M',
    sizeLabel: '284 MB',
    providerLabel: 'FunctionGemma',
    mobileUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task',
    desktopUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
    description:
        'Fastest option for turning search requests into tags and filters.',
    modelType: ModelType.functionGemma,
    fileType: ModelFileType.task,
  ),
  _DownloadableModel(
    name: 'Qwen3 0.6B',
    sizeLabel: '586 MB',
    providerLabel: 'Qwen',
    mobileUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    description: 'Balanced small model for better language understanding.',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
  ),
  _DownloadableModel(
    name: 'Qwen 2.5 1.5B Instruct',
    sizeLabel: '1.6 GB',
    providerLabel: 'Qwen',
    mobileUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    description:
        'Larger text model for stronger devices and better request parsing.',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
  ),
  _DownloadableModel(
    name: 'Phi-4 Mini Instruct',
    sizeLabel: '3.9 GB',
    providerLabel: 'Phi',
    mobileUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    description:
        'Large option for high-end devices; expect slower downloads and startup.',
    modelType: ModelType.general,
    fileType: ModelFileType.task,
  ),
];

final _recommendedLocalAiModel = _downloadableLocalAiModels.first;

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
  String _localAiProvider = _recommendedLocalAiModel.providerLabel;
  _DownloadableModel _selectedModel = _recommendedLocalAiModel;
  String? _downloadedModelName;
  double _imageQuality = 0.85;
  double _aiContextItems = 24;
  double? _downloadProgress;
  final _localEndpointController = TextEditingController(
    text: 'http://127.0.0.1:11434',
  );

  bool get _hasDownloadedModel => _downloadedModelName != null;

  Future<void> _downloadRecommendedModel() async {
    if (_isDownloadingModel) return;

    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = null;
    });

    try {
      await FlutterGemma.initialize();
      final modelToDownload = _selectedModel;
      final installation =
          await FlutterGemma.installModel(
            modelType: modelToDownload.modelType,
            fileType: modelToDownload.fileType,
          ).fromNetwork(modelToDownload.url).withProgress((progress) {
            if (mounted) setState(() => _downloadProgress = progress / 100);
          }).install();

      if (!mounted) return;
      setState(() {
        _downloadedModelName = modelToDownload.name;
        _useLocalAi = true;
        _localAiProvider = modelToDownload.providerLabel;
        _downloadProgress = 1;
      });
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
    super.dispose();
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
                    'These controls are local for now, but the page is fully interactive so we can keep building on top of it.',
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
                  subtitle: 'Hide extra chrome while reading pages.',
                  value: _immersiveReader,
                  onChanged: (value) {
                    setState(() => _immersiveReader = value);
                    showInfoToast(
                      context,
                      value
                          ? 'Immersive reader enabled.'
                          : 'Reader chrome will stay visible.',
                    );
                  },
                ),
                _SwitchRow(
                  icon: Icons.animation_rounded,
                  title: 'Motion effects',
                  subtitle: 'Keep subtle transitions and glass shimmer.',
                  value: _enableMotionEffects,
                  onChanged: (value) {
                    setState(() => _enableMotionEffects = value);
                    showInfoToast(
                      context,
                      value
                          ? 'Motion effects enabled.'
                          : 'Motion effects reduced.',
                    );
                  },
                ),
                _SliderRow(
                  icon: Icons.hd_rounded,
                  title: 'Image quality',
                  subtitle: 'Balances sharper pages against faster loading.',
                  value: _imageQuality,
                  onChanged: (value) => setState(() => _imageQuality = value),
                  onChangeEnd: (value) {
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
                  subtitle: 'Avoid large transfers on mobile data.',
                  value: _downloadOnWifiOnly,
                  onChanged: (value) {
                    setState(() => _downloadOnWifiOnly = value);
                    showInfoToast(
                      context,
                      value
                          ? 'Downloads are now limited to Wi-Fi.'
                          : 'Downloads can use any network.',
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
                  subtitle: 'Safer browsing while the filter system is basic.',
                  value: !_allowExplicitContent,
                  onChanged: (value) {
                    setState(() => _allowExplicitContent = !value);
                    showInfoToast(
                      context,
                      value
                          ? 'Explicit content will stay hidden.'
                          : 'Explicit content may appear in future feeds.',
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
              title: 'Local AI',
              subtitle:
                  'Model controls for local-only profile summaries and search interpretation.',
              children: [
                _OptionRow(
                  icon: Icons.hub_rounded,
                  title: 'Provider',
                  subtitle: 'Pick the local model runner Majika should target.',
                  value: _localAiProvider,
                  options: const [
                    'FunctionGemma',
                    'Qwen',
                    'Phi',
                    'External local server',
                    'Fallback rules only',
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _localAiProvider = value);
                    showInfoToast(context, 'Local AI provider set to $value.');
                  },
                ),
                _ModelDownloadCard(
                  models: _downloadableLocalAiModels,
                  selectedModel: _selectedModel,
                  isDownloading: _isDownloadingModel,
                  progress: _downloadProgress,
                  downloadedName: _downloadedModelName,
                  onModelSelected: (model) {
                    setState(() {
                      _selectedModel = model;
                      _localAiProvider = model.providerLabel;
                    });
                  },
                  onDownload: _downloadRecommendedModel,
                ),
                _TextFieldRow(
                  fieldKey: const ValueKey('local-ai-endpoint'),
                  icon: Icons.dns_rounded,
                  title: 'Local server endpoint',
                  subtitle:
                      'Optional later path for Ollama, llama.cpp, or another local runner.',
                  controller: _localEndpointController,
                  hintText: 'http://127.0.0.1:11434',
                ),
                _SwitchRow(
                  icon: Icons.memory_rounded,
                  title: 'Use local model when available',
                  subtitle:
                      'Falls back to rules until a Gemma model is imported.',
                  value: _useLocalAi,
                  onChanged: (value) {
                    setState(() => _useLocalAi = value);
                    showInfoToast(
                      context,
                      value
                          ? 'Local AI will be used once a model is configured.'
                          : 'Majika will use deterministic local rules.',
                    );
                  },
                ),
                _SwitchRow(
                  icon: Icons.manage_search_rounded,
                  title: 'AI search interpretation',
                  subtitle:
                      'Let the local model choose tags, formats, and filters from requests.',
                  value: _useAiForSearch,
                  onChanged: (value) {
                    setState(() => _useAiForSearch = value);
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
                    showInfoToast(
                      context,
                      'Local AI context limit set to ${value.round()} items.',
                    );
                  },
                ),
                _ActionRow(
                  icon: Icons.file_open_rounded,
                  title: 'Import Gemma model',
                  subtitle:
                      'Planned: choose a .litertlm model file for flutter_gemma.',
                  onTap: () =>
                      showFeatureComingSoon(context, 'Local model import'),
                ),
                _InfoRow(
                  icon: Icons.offline_bolt_rounded,
                  title: 'Current provider',
                  subtitle: _useLocalAi && _hasDownloadedModel
                      ? '${_downloadedModelName ?? 'Local model'} is active for search interpretation'
                      : 'Deterministic fallback rules until a model is configured',
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
  final String name;
  final String sizeLabel;
  final String providerLabel;
  final String mobileUrl;
  final String desktopUrl;
  final String description;
  final ModelType modelType;
  final ModelFileType fileType;

  const _DownloadableModel({
    required this.name,
    required this.sizeLabel,
    required this.providerLabel,
    required this.mobileUrl,
    required this.desktopUrl,
    required this.description,
    required this.modelType,
    this.fileType = ModelFileType.task,
  });

  String get url {
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    return isDesktop ? desktopUrl : mobileUrl;
  }
}

class _ModelDownloadCard extends StatelessWidget {
  final List<_DownloadableModel> models;
  final _DownloadableModel selectedModel;
  final bool isDownloading;
  final double? progress;
  final String? downloadedName;
  final ValueChanged<_DownloadableModel> onModelSelected;
  final VoidCallback onDownload;

  const _ModelDownloadCard({
    required this.models,
    required this.selectedModel,
    required this.isDownloading,
    required this.progress,
    required this.downloadedName,
    required this.onModelSelected,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloaded = downloadedName == selectedModel.name;

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
                  Icons.download_for_offline_rounded,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonHideUnderline(
                      child: DropdownButton<_DownloadableModel>(
                        value: selectedModel,
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
                              child: Text(model.name),
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
                      '${selectedModel.sizeLabel} · ${selectedModel.providerLabel}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
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
              ),
            ],
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
          Text(label, style: const TextStyle(color: Colors.white)),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: Colors.white70),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              subtitle,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: value,
            dropdownColor: const Color(0xFF1A1F27),
            iconEnabledColor: Colors.white70,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(context),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text(option)),
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

  const _TextFieldRow({
    this.fieldKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: Colors.white70),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              subtitle,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          TextField(
            key: fieldKey,
            controller: controller,
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
          ListTile(
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      onTap: onTap,
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
    );
  }
}
