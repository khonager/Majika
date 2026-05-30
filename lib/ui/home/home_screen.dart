import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/recommendations/taste_engine.dart';
import 'package:majika/core/services/anilist_service.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';

class HomeScreen extends StatefulWidget {
  final MediaService? mediaService;
  final TasteEngine? tasteEngine;
  final LocalAiService? aiService;

  const HomeScreen({
    super.key,
    this.mediaService,
    this.tasteEngine,
    this.aiService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MediaService _mediaService;
  late final TasteEngine _tasteEngine;
  late final LocalAiService _aiService;
  final TextEditingController _userNameController = TextEditingController();

  TasteProfile? _profile;
  List<Recommendation> _recommendations = [];
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _mediaService = widget.mediaService ?? AniListService();
    _tasteEngine = widget.tasteEngine ?? TasteEngine();
    _aiService = widget.aiService ?? const DeterministicLocalAiService();
  }

  @override
  void dispose() {
    _userNameController.dispose();
    super.dispose();
  }

  Future<void> _importAniListProfile() async {
    final userName = _userNameController.text.trim();
    if (userName.isEmpty) {
      showErrorToast(context, 'Enter an AniList username first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final library = await _mediaService.fetchUserLibrary(userName);
      final candidates = await _mediaService.fetchRecommendationCandidates();
      final profile = _tasteEngine.buildProfile(userName, library);
      final recommendations = _tasteEngine.rankCandidates(profile, candidates);

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _recommendations = recommendations;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111419), Color(0xFF0B0D10), Color(0xFF191C20)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;
              final shell = _ContentShell(
                profile: _profile,
                recommendations: _recommendations,
                isLoading: _isLoading,
                error: _error,
                aiService: _aiService,
                userNameController: _userNameController,
                onImport: _importAniListProfile,
              );

              if (isDesktop) {
                return Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                        child: shell,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                      child: _ServiceDock(
                        isDesktop: true,
                        onSettingsTap: _openSettings,
                        onUnavailableTap: (label) =>
                            showFeatureComingSoon(context, label),
                      ),
                    ),
                  ],
                );
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _ServiceDock(
                      isDesktop: false,
                      onSettingsTap: _openSettings,
                      onUnavailableTap: (label) =>
                          showFeatureComingSoon(context, label),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: shell),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ContentShell extends StatelessWidget {
  final TasteProfile? profile;
  final List<Recommendation> recommendations;
  final bool isLoading;
  final String? error;
  final LocalAiService aiService;
  final TextEditingController userNameController;
  final VoidCallback onImport;

  const _ContentShell({
    required this.profile,
    required this.recommendations,
    required this.isLoading,
    required this.error,
    required this.aiService,
    required this.userNameController,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.2,
                      colors: [
                        const Color(0xFF89D6B3).withValues(alpha: 0.09),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShellHeader(profile: profile, aiService: aiService),
                    const SizedBox(height: 14),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: profile == null
                            ? _ConnectState(
                                key: const ValueKey('connect'),
                                isLoading: isLoading,
                                error: error,
                                controller: userNameController,
                                onImport: onImport,
                              )
                            : _RecommendationState(
                                key: const ValueKey('recommendations'),
                                profile: profile!,
                                recommendations: recommendations,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  final TasteProfile? profile;
  final LocalAiService aiService;

  const _ShellHeader({required this.profile, required this.aiService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Majika',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                profile == null
                    ? 'Build a local taste profile from AniList.'
                    : '@${profile!.userName} · ${profile!.primaryTaste}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.64),
                ),
              ),
            ],
          ),
        ),
        _StatusPill(
          icon: Icons.auto_awesome_rounded,
          label: aiService.isConfigured ? 'Local AI' : 'Local rules',
        ),
      ],
    );
  }
}

class _ConnectState extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final TextEditingController controller;
  final VoidCallback onImport;

  const _ConnectState({
    super.key,
    required this.isLoading,
    required this.error,
    required this.controller,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.hub_rounded,
                color: Theme.of(context).colorScheme.secondary,
                size: 42,
              ),
              const SizedBox(height: 18),
              Text(
                'Connect AniList',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Enter a public AniList username. Majika will read anime and manga lists, build a local taste profile, then rank current releases against it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                enabled: !isLoading,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onImport(),
                decoration: InputDecoration(
                  hintText: 'AniList username',
                  prefixIcon: const Icon(Icons.person_search_rounded),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFF9AA8)),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isLoading ? null : onImport,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(isLoading ? 'Importing profile' : 'Build profile'),
              ),
              const SizedBox(height: 14),
              Text(
                'OAuth and Firebase sync are designed for later; this slice stays local-first.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationState extends StatelessWidget {
  final TasteProfile profile;
  final List<Recommendation> recommendations;

  const _RecommendationState({
    super.key,
    required this.profile,
    required this.recommendations,
  });

  @override
  Widget build(BuildContext context) {
    final topPick = recommendations.isEmpty ? null : recommendations.first;
    final otherPicks = recommendations.skip(1).take(18).toList();

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TasteSummary(profile: profile),
                  const SizedBox(height: 14),
                  if (topPick == null)
                    _EmptyRecommendations(profile: profile)
                  else
                    _TopRecommendationCard(recommendation: topPick),
                  const SizedBox(height: 18),
                  Text(
                    'More for this profile',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (otherPicks.isEmpty)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else
              SliverList.separated(
                itemBuilder: (context, index) {
                  return _RecommendationTile(recommendation: otherPicks[index]);
                },
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemCount: otherPicks.length,
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: _CurrentActivityBar(item: profile.recentActivity),
        ),
      ],
    );
  }
}

class _TasteSummary extends StatelessWidget {
  final TasteProfile profile;

  const _TasteSummary({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: profile.favoriteGenres
                .take(5)
                .map((genre) => _TextChip(label: genre))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _TopRecommendationCard extends StatelessWidget {
  final Recommendation recommendation;

  const _TopRecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final item = recommendation.item;
    final theme = Theme.of(context);

    return _GlassCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 250,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 132,
              child: _CoverImage(item: item, borderRadius: 24),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _StatusPill(
                      icon: Icons.star_rounded,
                      label: 'Top recommendation',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      recommendation.reason,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.38,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: recommendation.signals
                          .take(4)
                          .map((signal) => _TextChip(label: signal))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  final Recommendation recommendation;

  const _RecommendationTile({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final item = recommendation.item;
    final theme = Theme.of(context);

    return _GlassCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 96,
            child: _CoverImage(item: item, borderRadius: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  recommendation.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ScoreRing(score: recommendation.matchScore),
        ],
      ),
    );
  }
}

class _CurrentActivityBar extends StatelessWidget {
  final MediaItem? item;

  const _CurrentActivityBar({required this.item});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF89D6B3).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item == null
                      ? 'No current activity found'
                      : 'Current / latest',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item?.title ?? 'Import a profile with current list entries.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.graphic_eq_rounded, color: Colors.white70),
        ],
      ),
    );
  }
}

class _EmptyRecommendations extends StatelessWidget {
  final TasteProfile profile;

  const _EmptyRecommendations({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            color: Colors.white70,
            size: 36,
          ),
          const SizedBox(height: 10),
          Text(
            'Profile imported, but no recommendations ranked high enough yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceDock extends StatelessWidget {
  final bool isDesktop;
  final VoidCallback onSettingsTap;
  final ValueChanged<String> onUnavailableTap;

  const _ServiceDock({
    required this.isDesktop,
    required this.onSettingsTap,
    required this.onUnavailableTap,
  });

  @override
  Widget build(BuildContext context) {
    final children = [
      _DockButton(
        icon: Icons.home_rounded,
        label: 'Home',
        isActive: true,
        onTap: () {},
      ),
      _DockButton(
        icon: Icons.animation_rounded,
        label: 'AniList',
        isActive: true,
        onTap: () => onUnavailableTap('AniList OAuth'),
      ),
      _DockButton(
        icon: Icons.sports_esports_rounded,
        label: 'Steam',
        onTap: () => onUnavailableTap('Steam'),
      ),
      _DockButton(
        icon: Icons.local_movies_rounded,
        label: 'Movies/TV',
        onTap: () => onUnavailableTap('Movies and TV'),
      ),
      _DockButton(
        icon: Icons.add_rounded,
        label: 'Add service',
        onTap: () => onUnavailableTap('Add service'),
      ),
      if (!isDesktop) const Spacer(),
      _DockButton(
        icon: Icons.settings_rounded,
        label: 'Settings',
        onTap: onSettingsTap,
      ),
      _DockButton(
        icon: Icons.person_rounded,
        label: 'Profile',
        onTap: () => onUnavailableTap('Profile'),
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: isDesktop ? double.infinity : 66,
          height: isDesktop ? 78 : double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 12 : 8,
            vertical: isDesktop ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: isDesktop
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...children.take(5),
                    const Spacer(),
                    ...children.skip(5),
                  ],
                )
              : Column(children: children),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DockButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? Theme.of(context).colorScheme.secondary
        : Colors.white.withValues(alpha: 0.72);

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: color),
          style: IconButton.styleFrom(
            backgroundColor: isActive
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            fixedSize: const Size(46, 46),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF171A20).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  final MediaItem item;
  final double borderRadius;

  const _CoverImage({required this.item, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: Colors.white.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white54,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: item.hasCover
          ? Image.network(
              item.coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            )
          : fallback,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF89D6B3).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF89D6B3).withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFBDEECD)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEAF5ED),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextChip extends StatelessWidget {
  final String label;

  const _TextChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;

  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    final normalized = min(0.99, score / 16);
    return SizedBox.square(
      dimension: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: normalized,
            strokeWidth: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: Theme.of(context).colorScheme.secondary,
          ),
          Text(
            '${(normalized * 100).round()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
