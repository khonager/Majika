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
import 'package:majika/core/services/media_service.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:url_launcher/url_launcher.dart';

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
    _mediaService = widget.mediaService ?? AniListService();
    _tasteEngine = widget.tasteEngine ?? TasteEngine();
    _aiService = widget.aiService ?? const FlutterGemmaLocalAiService();
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
      final libraryFuture = _mediaService.fetchUserLibrary(userName);
      final signalsFuture = _mediaService.fetchTasteSignals(userName);
      final candidatesFuture = _mediaService.fetchRecommendationCandidates();
      final serviceTagsFuture = _mediaService.fetchAvailableTags();
      final library = await libraryFuture;
      final signals = await signalsFuture;
      final candidates = await candidatesFuture;
      final serviceTags = await serviceTagsFuture;
      final profile = _tasteEngine.buildProfile(
        userName,
        library,
        signals: signals,
      );
      final recommendations = _tasteEngine.rankCandidates(profile, candidates);

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

      if (!mounted) return;
      setState(() {
        _recommendationQuery = query;
        _candidates = candidates;
        _recommendations = recommendations;
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
    return {
      ...RecommendationQuery.browsableTags,
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

Future<void> _openMediaOnAniList(BuildContext context, MediaItem item) async {
  final fallbackId = item.id.startsWith('anilist_')
      ? item.id.replaceFirst('anilist_', '')
      : '';
  final url = item.siteUrl.isNotEmpty
      ? item.siteUrl
      : fallbackId.isNotEmpty
      ? 'https://anilist.co/${item.mediaType.toLowerCase()}/$fallbackId'
      : '';
  final uri = Uri.tryParse(url);
  if (uri == null || url.isEmpty) {
    showErrorToast(context, 'No AniList page is available for this item.');
    return;
  }

  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    showErrorToast(context, 'Could not open AniList.');
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
  final VoidCallback onSignOut;
  final VoidCallback onSwitchUser;
  final RecommendationQuery query;
  final bool isRefreshingRecommendations;
  final List<String> availableTags;
  final ValueChanged<RecommendationQuery> onQueryChanged;

  const _ContentShell({
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
                    _ShellHeader(
                      profile: profile,
                      aiService: aiService,
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
                                onImport: onImport,
                              )
                            : _RecommendationState(
                                key: const ValueKey('recommendations'),
                                profile: profile!,
                                recommendations: recommendations,
                                query: query,
                                isRefreshing: isRefreshingRecommendations,
                                availableTags: availableTags,
                                onQueryChanged: onQueryChanged,
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
  final VoidCallback onSignOut;
  final VoidCallback onSwitchUser;

  const _ShellHeader({
    required this.profile,
    required this.aiService,
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
                  ? 'Build a local taste profile from AniList.'
                  : '@${profile!.userName} · ${profile!.primaryTaste}',
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
  final RecommendationQuery query;
  final bool isRefreshing;
  final List<String> availableTags;
  final ValueChanged<RecommendationQuery> onQueryChanged;

  const _RecommendationState({
    super.key,
    required this.profile,
    required this.recommendations,
    required this.query,
    required this.isRefreshing,
    required this.availableTags,
    required this.onQueryChanged,
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
                  _RecommendationSearchPanel(
                    query: query,
                    isRefreshing: isRefreshing,
                    availableTags: availableTags,
                    onQueryChanged: onQueryChanged,
                  ),
                  const SizedBox(height: 14),
                  if (topPick == null)
                    _EmptyRecommendations(profile: profile, query: query)
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

class _RecommendationSearchPanel extends StatefulWidget {
  final RecommendationQuery query;
  final bool isRefreshing;
  final List<String> availableTags;
  final ValueChanged<RecommendationQuery> onQueryChanged;

  const _RecommendationSearchPanel({
    required this.query,
    required this.isRefreshing,
    required this.availableTags,
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
    widget.onQueryChanged(
      widget.query.copyWith(request: _searchController.text.trim()),
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
                    hintText: 'Search a vibe, tag, format, or request',
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
              _FilterChipButton(
                key: const ValueKey('filter-type-anime'),
                label: 'Anime',
                selected: widget.query.mediaTypes.contains('ANIME'),
                onSelected: () => _toggleMediaType('ANIME'),
              ),
              _FilterChipButton(
                key: const ValueKey('filter-type-manga'),
                label: 'Manga',
                selected: widget.query.mediaTypes.contains('MANGA'),
                onSelected: () => _toggleMediaType('MANGA'),
              ),
              _FilterChipButton(
                key: const ValueKey('filter-adult'),
                label: 'Adult',
                selected: widget.query.includeAdult || widget.query.infersAdult,
                onSelected: _toggleAdult,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FilterSection(
            label: 'Format',
            children: RecommendationQuery.allFormats.map((format) {
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
      _ => format[0] + format.substring(1).toLowerCase(),
    };
  }

  void _toggleTag(String tag) {
    final tags = {...widget.query.selectedTags};
    tags.contains(tag) ? tags.remove(tag) : tags.add(tag);
    widget.onQueryChanged(widget.query.copyWith(selectedTags: tags));
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
        );
      },
    );
    if (selected == null) return;
    widget.onQueryChanged(widget.query.copyWith(selectedTags: selected));
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
  final VoidCallback onBrowse;
  final ValueChanged<String> onToggleTag;

  const _TagPickerSection({
    required this.availableTags,
    required this.selectedTags,
    required this.onBrowse,
    required this.onToggleTag,
  });

  @override
  Widget build(BuildContext context) {
    final visibleTags = selectedTags.isEmpty
        ? availableTags.take(6).toList()
        : selectedTags.take(8).toList();
    final hiddenCount = max(0, availableTags.length - visibleTags.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                selectedTags.isEmpty
                    ? 'Tags'
                    : 'Tags · ${selectedTags.length} selected',
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

  const _TagPickerSheet({
    required this.availableTags,
    required this.selectedTags,
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
  final VoidCallback onSelected;

  const _FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: Theme.of(
        context,
      ).colorScheme.secondary.withValues(alpha: 0.24),
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.08),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.72),
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
        const _StatusPill(
          icon: Icons.star_rounded,
          label: 'Top recommendation',
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
      message: 'Open on AniList',
      child: Semantics(
        button: true,
        label: 'Open ${item.title} on AniList',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openMediaOnAniList(context, item),
            child: child,
          ),
        ),
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
