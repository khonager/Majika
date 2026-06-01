import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/recommendations/taste_engine.dart';
import 'package:majika/core/services/anilist_service.dart';
import 'package:majika/core/services/firebase_steam_backend.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:majika/core/services/steam_service.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:majika/ui/profile/profile_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  final MediaService? mediaService;
  final List<MediaService>? mediaServices;
  final TasteEngine? tasteEngine;
  final LocalAiService? aiService;

  const HomeScreen({
    super.key,
    this.mediaService,
    this.mediaServices,
    this.tasteEngine,
    this.aiService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final List<MediaService> _mediaServices;
  late MediaService _mediaService;
  late final TasteEngine _tasteEngine;
  late final LocalAiService _aiService;
  final TextEditingController _userNameController = TextEditingController();

  TasteProfile? _profile;
  List<MediaItem> _candidates = [];
  List<String> _serviceTags = [];
  List<Recommendation> _recommendations = [];
  RecommendationQuery _recommendationQuery = const RecommendationQuery();
  String? _error;
  bool _isLoading = false;
  bool _isRefreshingRecommendations = false;
  bool _adultCandidatesLoaded = false;

  @override
  void initState() {
    super.initState();
    _mediaServices =
        widget.mediaServices ??
        (widget.mediaService == null
            ? [
                AniListService(),
                SteamService(protectedApi: FirebaseSteamProtectedApi()),
              ]
            : [widget.mediaService!]);
    _mediaService = _mediaServices.first;
    _tasteEngine = widget.tasteEngine ?? TasteEngine();
    _aiService = widget.aiService ?? const FlutterGemmaLocalAiService();
  }

  @override
  void dispose() {
    _userNameController.dispose();
    super.dispose();
  }

  Future<void> _importProfile() async {
    final userName = _userNameController.text.trim();
    if (userName.isEmpty) {
      showErrorToast(context, _mediaService.userNameEmptyMessage);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profileFuture = _mediaService.fetchUserProfile(userName);
      final libraryFuture = _mediaService.fetchUserLibrary(userName);
      final signalsFuture = _mediaService.fetchTasteSignals(userName);
      final candidatesFuture = _mediaService.fetchRecommendationCandidates();
      final serviceTagsFuture = _mediaService.fetchAvailableTags();
      final serviceProfile = await profileFuture;
      final library = await libraryFuture;
      final signals = await signalsFuture;
      final candidates = await candidatesFuture;
      final serviceTags = await serviceTagsFuture;
      final profile = _tasteEngine.buildProfile(
        serviceProfile?.userName ?? userName,
        library,
        signals: signals,
        serviceId: _mediaService.id,
        serviceName: _mediaService.displayName,
        displayName: serviceProfile?.displayName,
        avatarUrl: serviceProfile?.avatarUrl ?? '',
        profileUrl: serviceProfile?.profileUrl ?? '',
      );
      final recommendations = await _withChosenTopRecommendation(
        profile,
        _tasteEngine.rankCandidates(profile, candidates),
        const RecommendationQuery(),
      );

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _candidates = candidates;
        _serviceTags = serviceTags;
        _recommendations = recommendations;
        _recommendationQuery = const RecommendationQuery();
        _adultCandidatesLoaded = false;
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

  void _signOut() {
    setState(() {
      _profile = null;
      _candidates = [];
      _serviceTags = [];
      _recommendations = [];
      _recommendationQuery = const RecommendationQuery();
      _error = null;
      _isLoading = false;
      _isRefreshingRecommendations = false;
      _adultCandidatesLoaded = false;
      _userNameController.clear();
    });
  }

  void _switchUser() {
    final previousUser = _profile?.userName ?? _userNameController.text.trim();
    _signOut();
    _userNameController.text = previousUser;
  }

  void _selectService(MediaService service) {
    if (service.id == _mediaService.id) return;
    setState(() {
      _mediaService = service;
    });
    _signOut();
  }

  Future<void> _updateRecommendationQuery(RecommendationQuery rawQuery) async {
    final profile = _profile;
    if (profile == null) return;

    setState(() {
      _recommendationQuery = rawQuery;
      _isRefreshingRecommendations = true;
    });

    try {
      final query = await _aiService.interpretRecommendationRequest(
        rawQuery,
        availableTags: _availableTags,
        serviceName: _mediaService.displayName,
        allowedMediaTypes: _mediaService.supportedMediaTypes,
        allowedFormats: _mediaService.supportedFormats,
      );
      var candidates = _candidates;
      final needsAdultCandidates =
          (query.includeAdult || query.infersAdult) && !_adultCandidatesLoaded;

      if (query.isActive) {
        final searchedCandidates = await _mediaService
            .searchRecommendationCandidates(query);
        candidates = _dedupeCandidates([...searchedCandidates, ...candidates]);
      }

      if (needsAdultCandidates) {
        final adultCandidates = await _mediaService
            .fetchRecommendationCandidates(includeAdult: true);
        candidates = _dedupeCandidates([...candidates, ...adultCandidates]);
      }

      final recommendations = _tasteEngine.rankCandidates(
        profile,
        candidates,
        query: query,
      );
      final orderedRecommendations = await _withChosenTopRecommendation(
        profile,
        recommendations,
        query,
      );

      if (!mounted) return;
      setState(() {
        _recommendationQuery = query;
        _candidates = candidates;
        _recommendations = orderedRecommendations;
        _adultCandidatesLoaded = _adultCandidatesLoaded || needsAdultCandidates;
        _isRefreshingRecommendations = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isRefreshingRecommendations = false;
      });
      showErrorToast(context, 'Could not refresh recommendations: $error');
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
  }

  Future<List<Recommendation>> _withChosenTopRecommendation(
    TasteProfile profile,
    List<Recommendation> recommendations,
    RecommendationQuery query,
  ) async {
    if (recommendations.isEmpty) return recommendations;

    final chosen = await _aiService.chooseTopRecommendation(
      profile,
      recommendations,
      query: query,
    );
    if (chosen == null) return recommendations;

    return [
      chosen.copyWith(isTopPick: true),
      for (final recommendation in recommendations)
        if (recommendation.item.id != chosen.item.id)
          recommendation.copyWith(isTopPick: false),
    ];
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
                isMobileSurface: !isDesktop,
                profile: _profile,
                recommendations: _recommendations,
                isLoading: _isLoading,
                error: _error,
                aiService: _aiService,
                userNameController: _userNameController,
                mediaService: _mediaService,
                onImport: _importProfile,
                onSignOut: _signOut,
                onSwitchUser: _switchUser,
                query: _recommendationQuery,
                isRefreshingRecommendations: _isRefreshingRecommendations,
                availableTags: _availableTags,
                onQueryChanged: _updateRecommendationQuery,
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
                        services: _mediaServices,
                        activeServiceId: _mediaService.id,
                        onServiceTap: _selectService,
                        onSettingsTap: _openSettings,
                        onProfileTap: _openProfile,
                        onUnavailableTap: (label) =>
                            showFeatureComingSoon(context, label),
                      ),
                    ),
                  ],
                );
              }

              return _MobileLiquidShell(
                onSettingsTap: _openSettings,
                services: _mediaServices,
                activeServiceId: _mediaService.id,
                onServiceTap: _selectService,
                onUnavailableTap: (label) =>
                    showFeatureComingSoon(context, label),
                onProfileTap: _openProfile,
                child: shell,
              );
            },
          ),
        ),
      ),
    );
  }

  List<String> get _availableTags {
    final counts = <String, int>{};
    for (final tag in _profile?.favoriteGenres ?? const <String>[]) {
      counts.update(tag, (count) => count + 4, ifAbsent: () => 4);
    }
    for (final item in _candidates) {
      for (final tag in item.tags) {
        counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final baseTags = _mediaService.displayName == 'Steam'
        ? _serviceTags
        : RecommendationQuery.browsableTags;
    return {
      ...baseTags,
      ..._serviceTags,
      ...entries.map((entry) => entry.key),
    }.toList();
  }

  List<MediaItem> _dedupeCandidates(List<MediaItem> candidates) {
    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate.id)) candidate,
    ];
  }
}

Future<void> _openMedia(BuildContext context, MediaItem item) async {
  final fallbackId = item.id.startsWith('anilist_')
      ? item.id.replaceFirst('anilist_', '')
      : '';
  final steamFallbackId = item.id.startsWith('steam_')
      ? item.id.replaceFirst('steam_', '')
      : '';
  final url = item.siteUrl.isNotEmpty
      ? item.siteUrl
      : fallbackId.isNotEmpty
      ? 'https://anilist.co/${item.mediaType.toLowerCase()}/$fallbackId'
      : steamFallbackId.isNotEmpty
      ? 'https://store.steampowered.com/app/$steamFallbackId'
      : '';
  final uri = Uri.tryParse(url);
  if (uri == null || url.isEmpty) {
    showErrorToast(
      context,
      'No ${item.serviceLabel} page is available for this item.',
    );
    return;
  }

  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    showErrorToast(context, 'Could not open ${item.serviceLabel}.');
  }
}

class _ContentShell extends StatelessWidget {
  final bool isMobileSurface;
  final MediaService mediaService;
  final TasteProfile? profile;
  final List<Recommendation> recommendations;
  final bool isLoading;
  final String? error;
  final LocalAiService aiService;
  final TextEditingController userNameController;
  final VoidCallback onImport;
  final VoidCallback onSignOut;
  final VoidCallback onSwitchUser;
  final RecommendationQuery query;
  final bool isRefreshingRecommendations;
  final List<String> availableTags;
  final ValueChanged<RecommendationQuery> onQueryChanged;

  const _ContentShell({
    this.isMobileSurface = false,
    required this.mediaService,
    required this.profile,
    required this.recommendations,
    required this.isLoading,
    required this.error,
    required this.aiService,
    required this.userNameController,
    required this.onImport,
    required this.onSignOut,
    required this.onSwitchUser,
    required this.query,
    required this.isRefreshingRecommendations,
    required this.availableTags,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(isMobileSurface ? 0 : 34);
    final shellPadding = isMobileSurface
        ? const EdgeInsets.fromLTRB(14, 16, 14, 0)
        : const EdgeInsets.fromLTRB(18, 18, 18, 0);
    final shell = Container(
      decoration: BoxDecoration(
        color: isMobileSurface
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.055),
        borderRadius: borderRadius,
        border: isMobileSurface
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                    const Color(
                      0xFF89D6B3,
                    ).withValues(alpha: isMobileSurface ? 0.14 : 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: shellPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShellHeader(
                  profile: profile,
                  aiService: aiService,
                  serviceName: mediaService.displayName,
                  onSignOut: onSignOut,
                  onSwitchUser: onSwitchUser,
                ),
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
                            mediaService: mediaService,
                            onImport: onImport,
                          )
                        : _RecommendationState(
                            key: const ValueKey('recommendations'),
                            profile: profile!,
                            recommendations: recommendations,
                            query: query,
                            isRefreshing: isRefreshingRecommendations,
                            availableTags: availableTags,
                            mediaService: mediaService,
                            isMobileSurface: isMobileSurface,
                            onQueryChanged: onQueryChanged,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isMobileSurface) {
      return shell;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: shell,
      ),
    );
  }
}

class _MobileLiquidShell extends StatelessWidget {
  final Widget child;
  final List<MediaService> services;
  final String activeServiceId;
  final ValueChanged<MediaService> onServiceTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onProfileTap;
  final ValueChanged<String> onUnavailableTap;

  const _MobileLiquidShell({
    required this.child,
    required this.services,
    required this.activeServiceId,
    required this.onServiceTap,
    required this.onSettingsTap,
    required this.onProfileTap,
    required this.onUnavailableTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 88,
          bottom: 16,
          left: 6,
          child: _MobileLiquidRail(
            services: services,
            activeServiceId: activeServiceId,
            onServiceTap: onServiceTap,
            onSettingsTap: onSettingsTap,
            onProfileTap: onProfileTap,
            onUnavailableTap: onUnavailableTap,
          ),
        ),
      ],
    );
  }
}

class _ShellHeader extends StatelessWidget {
  final TasteProfile? profile;
  final LocalAiService aiService;
  final String serviceName;
  final VoidCallback onSignOut;
  final VoidCallback onSwitchUser;

  const _ShellHeader({
    required this.profile,
    required this.aiService,
    required this.serviceName,
    required this.onSignOut,
    required this.onSwitchUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
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
                  ? 'Build a local taste profile from $serviceName.'
                  : '@${profile!.displayName} · ${profile!.primaryTaste}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.64),
              ),
            ),
          ],
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusPill(
              icon: Icons.auto_awesome_rounded,
              label: aiService.isConfigured ? 'Local AI' : 'Local rules',
            ),
            if (profile != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Switch user',
                onPressed: onSwitchUser,
                icon: const Icon(Icons.switch_account_rounded),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ],
        );

        if (constraints.maxWidth < 360 && profile != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 8), actions],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    );
  }
}

class _ConnectState extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final TextEditingController controller;
  final MediaService mediaService;
  final VoidCallback onImport;

  const _ConnectState({
    super.key,
    required this.isLoading,
    required this.error,
    required this.controller,
    required this.mediaService,
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
                mediaService.connectTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                mediaService.connectDescription,
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
                  hintText: mediaService.userNameHint,
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
                label: Text(
                  isLoading
                      ? 'Importing profile'
                      : mediaService.importButtonLabel,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                mediaService.displayName == 'Steam'
                    ? 'Steam OpenID account linking is designed for later; this slice uses public data and a local API key.'
                    : 'OAuth and Firebase sync are designed for later; this slice stays local-first.',
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
  final RecommendationQuery query;
  final bool isRefreshing;
  final List<String> availableTags;
  final MediaService mediaService;
  final bool isMobileSurface;
  final ValueChanged<RecommendationQuery> onQueryChanged;

  const _RecommendationState({
    super.key,
    required this.profile,
    required this.recommendations,
    required this.query,
    required this.isRefreshing,
    required this.availableTags,
    required this.mediaService,
    required this.isMobileSurface,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final topPick = recommendations.isEmpty ? null : recommendations.first;
    final otherPicks = recommendations.skip(1).take(18).toList();
    final readableInset = EdgeInsets.only(left: isMobileSurface ? 54 : 0);

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: readableInset,
                    child: mediaService.displayName == 'Steam'
                        ? _SteamDashboardSummary(profile: profile)
                        : _TasteSummary(profile: profile),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: readableInset,
                    child: _RecommendationSearchPanel(
                      query: query,
                      isRefreshing: isRefreshing,
                      availableTags: availableTags,
                      mediaService: mediaService,
                      onQueryChanged: onQueryChanged,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (topPick == null)
                    Padding(
                      padding: readableInset,
                      child: _EmptyRecommendations(
                        profile: profile,
                        query: query,
                      ),
                    )
                  else
                    _TopRecommendationCard(recommendation: topPick),
                  const SizedBox(height: 18),
                  Padding(
                    padding: readableInset,
                    child: Text(
                      'More for this profile',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
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
          left: isMobileSurface ? 60 : 0,
          right: 0,
          bottom: isMobileSurface ? 14 : 12,
          child: _CurrentActivityBar(
            item: profile.recentActivity,
            isFloating: isMobileSurface,
          ),
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

class _SteamDashboardSummary extends StatelessWidget {
  final TasteProfile profile;

  const _SteamDashboardSummary({required this.profile});

  @override
  Widget build(BuildContext context) {
    final totalHours = profile.library.fold<int>(
      0,
      (total, item) => total + ((item.playtimeMinutes ?? 0) / 60).round(),
    );
    final mostPlayed = [...profile.library]
      ..sort(
        (a, b) => (b.playtimeMinutes ?? 0).compareTo(a.playtimeMinutes ?? 0),
      );

    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                backgroundImage: profile.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(profile.avatarUrl),
                child: profile.avatarUrl.isEmpty
                    ? const Icon(Icons.sports_esports_rounded)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${profile.library.length} games · $totalHours hours tracked',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final genre in profile.favoriteGenres.take(6))
                _TextChip(label: genre),
            ],
          ),
          if (mostPlayed.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final item = mostPlayed[index];
                  final hours = ((item.playtimeMinutes ?? 0) / 60).round();
                  return Container(
                    width: 190,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          height: 58,
                          child: _CoverImage(item: item, borderRadius: 10),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$hours h',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemCount: min(5, mostPlayed.length),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecommendationSearchPanel extends StatefulWidget {
  final RecommendationQuery query;
  final bool isRefreshing;
  final List<String> availableTags;
  final MediaService mediaService;
  final ValueChanged<RecommendationQuery> onQueryChanged;

  const _RecommendationSearchPanel({
    required this.query,
    required this.isRefreshing,
    required this.availableTags,
    required this.mediaService,
    required this.onQueryChanged,
  });

  @override
  State<_RecommendationSearchPanel> createState() =>
      _RecommendationSearchPanelState();
}

class _RecommendationSearchPanelState
    extends State<_RecommendationSearchPanel> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query.request);
  }

  @override
  void didUpdateWidget(covariant _RecommendationSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query.request != _searchController.text) {
      _searchController.text = widget.query.request;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submitRequest() {
    final nextRequest = _searchController.text.trim();
    final requestChanged = nextRequest != widget.query.request.trim();
    widget.onQueryChanged(
      widget.query.copyWith(
        request: nextRequest,
        aiSelectedTags: requestChanged
            ? <String>{}
            : widget.query.aiSelectedTags,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitRequest(),
                  decoration: InputDecoration(
                    hintText: widget.mediaService.searchPlaceholder,
                    prefixIcon: const Icon(Icons.manage_search_rounded),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Search recommendations',
                onPressed: widget.isRefreshing ? null : _submitRequest,
                icon: widget.isRefreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FilterSection(
            label: 'Type',
            children: [
              for (final mediaType in widget.mediaService.supportedMediaTypes)
                _FilterChipButton(
                  key: ValueKey('filter-type-${mediaType.toLowerCase()}'),
                  label: _mediaTypeLabel(mediaType),
                  selected: widget.query.mediaTypes.contains(mediaType),
                  onSelected: () => _toggleMediaType(mediaType),
                ),
              if (widget.mediaService.supportsAdultContent)
                _FilterChipButton(
                  key: const ValueKey('filter-adult'),
                  label: 'Adult',
                  selected:
                      widget.query.includeAdult || widget.query.infersAdult,
                  onSelected: _toggleAdult,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _FilterSection(
            label: widget.mediaService.displayName == 'Steam'
                ? 'Modes'
                : 'Format',
            children: widget.mediaService.supportedFormats.map((format) {
              return _FilterChipButton(
                key: ValueKey('filter-format-${format.toLowerCase()}'),
                label: _formatLabel(format),
                selected: widget.query.formats.contains(format),
                onSelected: () => _toggleFormat(format),
              );
            }).toList(),
          ),
          if (widget.availableTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TagPickerSection(
              availableTags: widget.availableTags,
              selectedTags: widget.query.selectedTags,
              aiSelectedTags: widget.query.aiSelectedTags,
              onBrowse: _openTagPicker,
              onToggleTag: _toggleTag,
            ),
          ],
          if (widget.query.isActive) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  widget.onQueryChanged(const RecommendationQuery());
                },
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Clear recommendation search'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatLabel(String format) {
    return switch (format) {
      'TV' => 'TV',
      'TV_SHORT' => 'TV Short',
      'MOVIE' => 'Movie',
      'OVA' => 'OVA',
      'ONA' => 'ONA',
      'MUSIC' => 'Music',
      'MANGA' => 'Manga',
      'NOVEL' => 'Novel',
      'SPECIAL' => 'Special',
      'ONE_SHOT' => 'One-shot',
      'SINGLE_PLAYER' => 'Single-player',
      'MULTIPLAYER' => 'Multiplayer',
      'CO_OP' => 'Co-op',
      'ONLINE_CO_OP' => 'Online co-op',
      'CONTROLLER' => 'Controller',
      'STEAM_DECK' => 'Steam Deck',
      _ => format[0] + format.substring(1).toLowerCase(),
    };
  }

  String _mediaTypeLabel(String mediaType) {
    return switch (mediaType) {
      'ANIME' => 'Anime',
      'MANGA' => 'Manga',
      'GAME' => 'Games',
      _ => mediaType,
    };
  }

  void _toggleTag(String tag) {
    final tags = {...widget.query.selectedTags};
    final aiTags = {...widget.query.aiSelectedTags}..remove(tag);
    tags.contains(tag) ? tags.remove(tag) : tags.add(tag);
    widget.onQueryChanged(
      widget.query.copyWith(selectedTags: tags, aiSelectedTags: aiTags),
    );
  }

  Future<void> _openTagPicker() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _TagPickerSheet(
          availableTags: widget.availableTags,
          selectedTags: widget.query.selectedTags,
          aiSelectedTags: widget.query.aiSelectedTags,
        );
      },
    );
    if (selected == null) return;
    widget.onQueryChanged(
      widget.query.copyWith(selectedTags: selected, aiSelectedTags: {}),
    );
  }

  void _toggleMediaType(String mediaType) {
    final mediaTypes = {...widget.query.mediaTypes};
    if (mediaTypes.contains(mediaType)) {
      mediaTypes.remove(mediaType);
    } else {
      mediaTypes
        ..clear()
        ..add(mediaType);
    }
    widget.onQueryChanged(widget.query.copyWith(mediaTypes: mediaTypes));
  }

  void _toggleFormat(String format) {
    final formats = {...widget.query.formats};
    formats.contains(format) ? formats.remove(format) : formats.add(format);
    widget.onQueryChanged(widget.query.copyWith(formats: formats));
  }

  void _toggleAdult() {
    widget.onQueryChanged(
      widget.query.copyWith(includeAdult: !widget.query.includeAdult),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _FilterSection({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.54),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(spacing: 7, runSpacing: 7, children: children),
      ],
    );
  }
}

class _TagPickerSection extends StatelessWidget {
  final List<String> availableTags;
  final Set<String> selectedTags;
  final Set<String> aiSelectedTags;
  final VoidCallback onBrowse;
  final ValueChanged<String> onToggleTag;

  const _TagPickerSection({
    required this.availableTags,
    required this.selectedTags,
    required this.aiSelectedTags,
    required this.onBrowse,
    required this.onToggleTag,
  });

  @override
  Widget build(BuildContext context) {
    final activeTags = {...selectedTags, ...aiSelectedTags};
    final visibleTags = activeTags.isEmpty
        ? availableTags.take(6).toList()
        : activeTags.take(8).toList();
    final hiddenCount = max(0, availableTags.length - visibleTags.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                activeTags.isEmpty
                    ? 'Tags'
                    : 'Tags · ${selectedTags.length} pinned · ${aiSelectedTags.length} AI',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.54),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('browse-tags-button'),
              onPressed: onBrowse,
              icon: const Icon(Icons.sell_rounded, size: 16),
              label: Text(selectedTags.isEmpty ? 'Browse tags' : 'Edit tags'),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final tag in visibleTags)
              _FilterChipButton(
                key: ValueKey('filter-tag-${tag.toLowerCase()}'),
                label: tag,
                selected: selectedTags.contains(tag),
                aiSelected:
                    aiSelectedTags.contains(tag) && !selectedTags.contains(tag),
                onSelected: () => onToggleTag(tag),
              ),
            if (hiddenCount > 0)
              ActionChip(
                label: Text('+$hiddenCount more'),
                avatar: const Icon(Icons.unfold_more_rounded, size: 16),
                onPressed: onBrowse,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                labelStyle: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TagPickerSheet extends StatefulWidget {
  final List<String> availableTags;
  final Set<String> selectedTags;
  final Set<String> aiSelectedTags;

  const _TagPickerSheet({
    required this.availableTags,
    required this.selectedTags,
    required this.aiSelectedTags,
  });

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  late final TextEditingController _searchController;
  late Set<String> _selectedTags;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedTags = {...widget.selectedTags};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final tags = widget.availableTags.where((tag) {
      if (_search.trim().isEmpty) return true;
      return tag.toLowerCase().contains(_search.toLowerCase().trim());
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: _GlassCard(
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose tags',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close tag picker',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('tag-picker-search'),
                controller: _searchController,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: 'Filter tags',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.22),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final tag in tags)
                        _FilterChipButton(
                          label: tag,
                          selected: _selectedTags.contains(tag),
                          aiSelected:
                              widget.aiSelectedTags.contains(tag) &&
                              !_selectedTags.contains(tag),
                          onSelected: () {
                            setState(() {
                              _selectedTags.contains(tag)
                                  ? _selectedTags.remove(tag)
                                  : _selectedTags.add(tag);
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(_selectedTags.clear),
                    icon: const Icon(Icons.clear_rounded),
                    label: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _selectedTags),
                    icon: const Icon(Icons.check_rounded),
                    label: Text('Apply ${_selectedTags.length}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool aiSelected;
  final VoidCallback onSelected;

  const _FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    this.aiSelected = false,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final aiAccent = const Color(0xFFB6A7FF);

    return FilterChip(
      label: Text(label),
      avatar: aiSelected
          ? const Icon(Icons.auto_awesome_rounded, size: 15)
          : null,
      selected: selected || aiSelected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: (aiSelected ? aiAccent : accent).withValues(alpha: 0.24),
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      side: BorderSide(
        color: selected || aiSelected
            ? (aiSelected ? aiAccent : accent).withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.08),
      ),
      labelStyle: TextStyle(
        color: selected || aiSelected
            ? Colors.white
            : Colors.white.withValues(alpha: 0.72),
        fontWeight: FontWeight.w700,
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

    return _OpenableRecommendation(
      item: item,
      child: _GlassCard(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 560;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 190,
                    child: _CoverImage(item: item, borderRadius: 24),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _TopRecommendationDetails(
                      recommendation: recommendation,
                      compact: true,
                    ),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  height: 282,
                  child: _CoverImage(item: item, borderRadius: 24),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _TopRecommendationDetails(
                      recommendation: recommendation,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopRecommendationDetails extends StatelessWidget {
  final Recommendation recommendation;
  final bool compact;

  const _TopRecommendationDetails({
    required this.recommendation,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final item = recommendation.item;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusPill(
          icon: recommendation.isAiPick
              ? Icons.auto_awesome_rounded
              : Icons.star_rounded,
          label: recommendation.isAiPick
              ? 'AI recommendation'
              : 'Top recommendation',
        ),
        const SizedBox(height: 12),
        Text(
          item.title,
          maxLines: compact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          recommendation.reason,
          maxLines: compact ? 3 : 4,
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
              .take(compact ? 3 : 4)
              .map((signal) => _TextChip(label: signal))
              .toList(),
        ),
      ],
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

    return _OpenableRecommendation(
      item: item,
      child: _GlassCard(
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
      ),
    );
  }
}

class _OpenableRecommendation extends StatelessWidget {
  final MediaItem item;
  final Widget child;

  const _OpenableRecommendation({required this.item, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open on ${item.serviceLabel}',
      child: Semantics(
        button: true,
        label: 'Open ${item.title} on ${item.serviceLabel}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openMedia(context, item),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CurrentActivityBar extends StatelessWidget {
  final MediaItem? item;
  final bool isFloating;

  const _CurrentActivityBar({required this.item, this.isFloating = false});

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Container(
          width: isFloating ? 42 : 44,
          height: isFloating ? 42 : 44,
          decoration: BoxDecoration(
            color: const Color(0xFF89D6B3).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(isFloating ? 18 : 14),
            border: isFloating
                ? Border.all(color: Colors.white.withValues(alpha: 0.2))
                : null,
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
                item == null ? 'No current activity found' : 'Current / latest',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.54),
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
        Icon(
          isFloating ? Icons.equalizer_rounded : Icons.graphic_eq_rounded,
          color: Colors.white70,
        ),
      ],
    );

    if (!isFloating) {
      return _GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: content,
      );
    }

    return _LiquidGlassPod(
      key: const ValueKey('mobile-current-activity-glass'),
      borderRadius: BorderRadius.circular(30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: content,
    );
  }
}

class _EmptyRecommendations extends StatelessWidget {
  final TasteProfile profile;
  final RecommendationQuery query;

  const _EmptyRecommendations({required this.profile, required this.query});

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
            query.isActive
                ? 'No matches for this recommendation search yet. Try fewer tags or a broader format.'
                : 'Profile imported, but no recommendations ranked high enough yet.',
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

class _MobileLiquidRail extends StatelessWidget {
  final List<MediaService> services;
  final String activeServiceId;
  final ValueChanged<MediaService> onServiceTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onProfileTap;
  final ValueChanged<String> onUnavailableTap;

  const _MobileLiquidRail({
    required this.services,
    required this.activeServiceId,
    required this.onServiceTap,
    required this.onSettingsTap,
    required this.onProfileTap,
    required this.onUnavailableTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('mobile-liquid-rail'),
      width: 50,
      child: Column(
        children: [
          _LiquidGlassPod(
            borderRadius: BorderRadius.circular(26),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LiquidRailButton(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isActive: true,
                  onTap: () {},
                ),
                for (final service in services)
                  _LiquidRailButton(
                    icon: _serviceIcon(service),
                    label: service.displayName,
                    isActive: activeServiceId == service.id,
                    onTap: () => onServiceTap(service),
                  ),
                _LiquidRailButton(
                  icon: Icons.local_movies_rounded,
                  label: 'Movies/TV',
                  onTap: () => onUnavailableTap('Movies and TV'),
                ),
                _LiquidRailButton(
                  icon: Icons.add_rounded,
                  label: 'Add service',
                  onTap: () => onUnavailableTap('Add service'),
                ),
              ],
            ),
          ),
          const Spacer(),
          _LiquidGlassPod(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LiquidRailButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: onSettingsTap,
                ),
                _LiquidRailButton(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  onTap: onProfileTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _serviceIcon(MediaService service) {
  return service.displayName == 'Steam'
      ? Icons.sports_esports_rounded
      : Icons.animation_rounded;
}

class _LiquidGlassPod extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  const _LiquidGlassPod({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(-6, -8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.035),
                        Colors.black.withValues(alpha: 0.05),
                      ],
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                left: 8,
                right: 8,
                height: 1.2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidRailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _LiquidRailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.secondary;
    final iconColor = isActive
        ? const Color(0xFF0F1713)
        : Colors.white.withValues(alpha: 0.72);

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: iconColor, size: 21),
          style: IconButton.styleFrom(
            backgroundColor: isActive
                ? activeColor.withValues(alpha: 0.84)
                : Colors.white.withValues(alpha: 0.015),
            fixedSize: const Size(40, 40),
            minimumSize: const Size(40, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const CircleBorder(),
            side: BorderSide(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.34)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            shadowColor: isActive
                ? activeColor.withValues(alpha: 0.7)
                : Colors.transparent,
            elevation: isActive ? 10 : 0,
          ),
        ),
      ),
    );
  }
}

class _ServiceDock extends StatelessWidget {
  final bool isDesktop;
  final List<MediaService> services;
  final String activeServiceId;
  final ValueChanged<MediaService> onServiceTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onProfileTap;
  final ValueChanged<String> onUnavailableTap;

  const _ServiceDock({
    required this.isDesktop,
    required this.services,
    required this.activeServiceId,
    required this.onServiceTap,
    required this.onSettingsTap,
    required this.onProfileTap,
    required this.onUnavailableTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryChildren = [
      _DockButton(
        icon: Icons.home_rounded,
        label: 'Home',
        isActive: true,
        onTap: () {},
      ),
      for (final service in services)
        _DockButton(
          icon: _serviceIcon(service),
          label: service.displayName,
          isActive: activeServiceId == service.id,
          onTap: () => onServiceTap(service),
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
    ];
    final secondaryChildren = [
      if (!isDesktop) const Spacer(),
      _DockButton(
        icon: Icons.settings_rounded,
        label: 'Settings',
        onTap: onSettingsTap,
      ),
      _DockButton(
        icon: Icons.person_rounded,
        label: 'Profile',
        onTap: onProfileTap,
      ),
    ];
    final children = [...primaryChildren, ...secondaryChildren];

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
                    ...primaryChildren,
                    const Spacer(),
                    ...secondaryChildren,
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
      constraints: const BoxConstraints(maxWidth: 190),
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFEAF5ED),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
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
    final normalized = (score / 100).clamp(0.0, 0.99);
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
