import 'package:flutter/material.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:majika/ui/shared/glass_panel.dart';

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
  double _imageQuality = 0.85;

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
          ListTile(
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
