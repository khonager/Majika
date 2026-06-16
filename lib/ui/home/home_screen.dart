import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:majika/core/ai/ai_console_log.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/recommendations/taste_engine.dart';
import 'package:majika/core/services/anilist_service.dart';
import 'package:majika/core/services/firebase_steam_backend.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:majika/core/services/steam_service.dart';
import 'package:majika/core/storage/local_profile_store.dart';
import 'package:majika/ui/settings/settings_screen.dart';
import 'package:majika/ui/profile/profile_screen.dart';
import 'package:majika/ui/shared/app_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ActiveSurface { home, service }

RecommendationQuery _storedQueryAfterInterpretation(
  RecommendationQuery query,
  MediaService service,
) {
  if (service.displayName != 'Steam' ||
      query.interpretedRequest.trim().isEmpty ||
      query.formats.isEmpty) {
    return query;
  }

  final explicitTextFormats = query
      .inferredFormats()
      .where(RecommendationQuery.steamFormats.contains)
      .map(RecommendationQuery.canonicalFormat)
      .toSet();
  final stickyFormats = {
    for (final format in query.formats)
      if (explicitTextFormats.contains(
        RecommendationQuery.canonicalFormat(format),
      ))
        RecommendationQuery.canonicalFormat(format),
  };
  return query.copyWith(formats: stickyFormats);
}

class _ServiceWorkspace {
  final MediaService service;
  TasteProfile? profile;
  List<MediaItem> candidates;
  List<MediaItem> baseCandidates;
  List<String> serviceTags;
  List<Recommendation> recommendations;
  RecommendationQuery query;
  String? error;
  bool isLoading;
  bool isRefreshingRecommendations;
  bool adultCandidatesLoaded;
  String userNameDraft;
  int? activeRecommendationSearchRunId;

  _ServiceWorkspace({required this.service})
    : candidates = [],
      baseCandidates = [],
      serviceTags = [],
      recommendations = [],
      query = const RecommendationQuery(),
      isLoading = false,
      isRefreshingRecommendations = false,
      adultCandidatesLoaded = false,
      userNameDraft = '';

  bool get hasProfile => profile != null;

  LocalProfileSession? toLocalSession() {
    final currentProfile = profile;
    if (currentProfile == null) return null;
    return LocalProfileSession(
      serviceId: service.id,
      profile: currentProfile,
      candidates: candidates,
      baseCandidates: baseCandidates,
      serviceTags: serviceTags,
      query: query,
      adultCandidatesLoaded: adultCandidatesLoaded,
      userNameDraft: userNameDraft,
    );
  }

  void restore(
    LocalProfileSession session, {
    required TasteEngine tasteEngine,
  }) {
    profile = session.profile;
    candidates = session.candidates;
    baseCandidates = session.baseCandidates.isEmpty
        ? session.candidates
        : session.baseCandidates;
    serviceTags = session.serviceTags;
    query = session.query;
    adultCandidatesLoaded = session.adultCandidatesLoaded;
    userNameDraft = session.userNameDraft.isNotEmpty
        ? session.userNameDraft
        : session.profile.userName;
    recommendations = tasteEngine.rankCandidates(
      session.profile,
      session.candidates,
      query: session.query,
    );
    error = null;
    isLoading = false;
    isRefreshingRecommendations = false;
    activeRecommendationSearchRunId = null;
  }

  void clear({String draft = ''}) {
    profile = null;
    candidates = [];
    baseCandidates = [];
    serviceTags = [];
    recommendations = [];
    query = const RecommendationQuery();
    error = null;
    isLoading = false;
    isRefreshingRecommendations = false;
    adultCandidatesLoaded = false;
    userNameDraft = draft;
    activeRecommendationSearchRunId = null;
  }
}

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
  late final LocalProfileStore _profileStore;
  late final Map<String, _ServiceWorkspace> _workspaces;
  final TextEditingController _userNameController = TextEditingController();

  _ActiveSurface _activeSurface = _ActiveSurface.home;
  RecommendationQuery _homeQuery = const RecommendationQuery();
  List<Recommendation> _homeRecommendations = [];
  Map<String, List<Recommendation>> _homeRecommendationsByService = {};
  String? _homeError;
  bool _isRefreshingHome = false;
  int _nextSearchRunId = 0;
  int? _activeHomeSearchRunId;
  AppProgressToast? _activeRecommendationProgressToast;
  AppProgressToast? _activeHomeProgressToast;
  final Map<String, List<AiChatMessage>> _chatMessagesBySurface = {};

  static const int _visibleAiTagCount = 4;

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
    _activeSurface = widget.mediaService == null
        ? _ActiveSurface.home
        : _ActiveSurface.service;
    _tasteEngine = widget.tasteEngine ?? TasteEngine();
    _aiService = widget.aiService ?? const FlutterGemmaLocalAiService();
    _profileStore = const LocalProfileStore();
    _workspaces = {
      for (final service in _mediaServices)
        service.id: _ServiceWorkspace(service: service),
    };
    _loadSavedSessions();
  }

  @override
  void dispose() {
    _activeRecommendationProgressToast?.dismiss();
    _activeHomeProgressToast?.dismiss();
    _userNameController.dispose();
    super.dispose();
  }

  Future<void> _importProfile() async {
    final workspace = _activeWorkspace;
    final userName = _userNameController.text.trim();
    if (userName.isEmpty) {
      showErrorToast(context, workspace.service.userNameEmptyMessage);
      return;
    }

    setState(() {
      workspace.isLoading = true;
      workspace.error = null;
      workspace.userNameDraft = userName;
    });

    try {
      final service = workspace.service;
      final initialQuery = RecommendationQuery(
        excludeAdult:
            service.supportsAdultContent && !await _allowsExplicitContent(),
      );
      final importResults = await Future.wait<Object?>([
        service.fetchUserProfile(userName),
        service.fetchUserLibrary(userName),
        service.fetchTasteSignals(userName),
        service.fetchRecommendationCandidates(
          includeAdult: initialQuery.includeAdult,
        ),
        service.fetchAvailableTags(),
      ]);
      final serviceProfile = importResults[0] as ServiceUserProfile?;
      final library = importResults[1] as List<MediaItem>;
      final signals = importResults[2] as UserTasteSignals;
      final candidates = importResults[3] as List<MediaItem>;
      final serviceTags = importResults[4] as List<String>;
      final profile = _tasteEngine.buildProfile(
        serviceProfile?.userName ?? userName,
        library,
        signals: signals,
        serviceId: service.id,
        serviceName: service.displayName,
        displayName: serviceProfile?.displayName,
        avatarUrl: serviceProfile?.avatarUrl ?? '',
        profileUrl: serviceProfile?.profileUrl ?? '',
      );
      final selection = await _withChosenTopRecommendation(
        service,
        profile,
        _tasteEngine.rankCandidates(profile, candidates, query: initialQuery),
        initialQuery,
      );
      final recommendations = selection.recommendations;
      final storedCandidates = _dedupeCandidates([
        ...candidates,
        if (selection.discoveredItem != null) selection.discoveredItem!,
      ]);

      if (!mounted) return;
      setState(() {
        workspace.profile = profile;
        workspace.candidates = storedCandidates;
        workspace.baseCandidates = candidates;
        workspace.serviceTags = serviceTags;
        workspace.recommendations = recommendations;
        workspace.query = initialQuery;
        workspace.adultCandidatesLoaded = initialQuery.includeAdult;
        workspace.isLoading = false;
        workspace.userNameDraft = userName;
      });
      unawaited(_persistWorkspace(workspace));
      _rebuildHomeRecommendationsSync();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        workspace.error = error.toString();
        workspace.isLoading = false;
      });
    }
  }

  void _signOut({bool keepDraft = false}) {
    final workspace = _activeWorkspace;
    final draft = keepDraft
        ? workspace.profile?.userName ?? _userNameController.text.trim()
        : '';
    setState(() {
      workspace.clear(draft: draft);
      _userNameController.text = draft;
    });
    unawaited(_profileStore.removeSession(workspace.service.id));
    _rebuildHomeRecommendationsSync();
  }

  void _switchUser() {
    _signOut(keepDraft: true);
  }

  void _selectService(MediaService service) {
    _activeWorkspace.userNameDraft = _userNameController.text.trim();
    setState(() {
      _mediaService = service;
      _activeSurface = _ActiveSurface.service;
      final nextWorkspace = _activeWorkspace;
      _userNameController.text = nextWorkspace.userNameDraft.isNotEmpty
          ? nextWorkspace.userNameDraft
          : nextWorkspace.profile?.userName ?? '';
    });
  }

  void _selectHome() {
    _activeWorkspace.userNameDraft = _userNameController.text.trim();
    setState(() => _activeSurface = _ActiveSurface.home);
  }

  Future<void> _updateRecommendationQuery(RecommendationQuery rawQuery) async {
    final workspace = _activeWorkspace;
    final profile = workspace.profile;
    if (profile == null) return;
    final allowExplicitContent = await _allowsExplicitContent();
    final requestQuery = rawQuery.copyWith(
      includeAdult: false,
      excludeAdult:
          workspace.service.supportsAdultContent && !allowExplicitContent,
    );
    if (!mounted) return;
    final searchRunId = ++_nextSearchRunId;

    setState(() {
      workspace.query = requestQuery;
      workspace.isRefreshingRecommendations = true;
      workspace.activeRecommendationSearchRunId = searchRunId;
    });
    final aiLog = AiConsoleLog();
    final progressToast = showProgressToast(
      context,
      'Reading your request for ${workspace.service.displayName}...',
      consoleLog: aiLog,
    );
    _activeRecommendationProgressToast = progressToast;

    try {
      await runZoned(
        () async {
          progressToast.update(
            'Interpreting request with local AI or rules...',
          );
          final query = await _aiService.interpretRecommendationRequest(
            requestQuery,
            availableTags: _availableTags,
            serviceName: workspace.service.displayName,
            allowedMediaTypes: workspace.service.supportedMediaTypes,
            allowedFormats: workspace.service.supportedFormats,
          );
          _logQueryInterpretation(aiLog, query);
          var baseCandidates = workspace.baseCandidates;
          var candidates = query.isActive ? <MediaItem>[] : [...baseCandidates];
          var requestSeedCandidates = <MediaItem>[];
          final needsAdultCandidates =
              query.allowsAdult && !workspace.adultCandidatesLoaded;
          final preferAiDiscoveryFirst =
              query.isActive && _prefersAiDiscoveryFirst(workspace.service);

          if (preferAiDiscoveryFirst) {
            progressToast.update(
              'Asking AI for likely ${workspace.service.displayName} matches...',
            );
            final aiDiscovered = await _discoverAiSuggestedItems(
              service: workspace.service,
              profile: profile,
              knownRecommendations: const [],
              query: query,
            );
            _logAiDiscoveryResults(
              aiLog,
              workspace.service.displayName,
              aiDiscovered,
              usedAsPrimarySearch: true,
            );
            if (aiDiscovered.isNotEmpty) {
              requestSeedCandidates = _dedupeCandidates([
                ...requestSeedCandidates,
                ...aiDiscovered,
              ]);
              candidates = _dedupeCandidates([...aiDiscovered, ...candidates]);
              _publishRecommendationSearchStage(
                workspace: workspace,
                profile: profile,
                query: query,
                candidates: candidates,
                requestSeedCandidates: requestSeedCandidates,
                searchRunId: searchRunId,
              );
            }
          }

          if (_shouldSearchServiceCandidates(
            workspace.service,
            query: query,
            candidates: candidates,
            preferAiDiscoveryFirst: preferAiDiscoveryFirst,
          )) {
            progressToast.update(
              candidates.isEmpty
                  ? 'Searching ${workspace.service.displayName} candidates...'
                  : 'Searching for more ${workspace.service.displayName} candidates...',
            );
            final searchedCandidates = await workspace.service
                .searchRecommendationCandidates(query);
            _logCandidateResults(
              aiLog,
              workspace.service.displayName,
              searchedCandidates,
              emptyMessage:
                  'Direct store search did not find any clear matches yet.',
            );
            candidates = _dedupeCandidates([
              ...searchedCandidates,
              ...candidates,
            ]);
            if (candidates.isNotEmpty) {
              _publishRecommendationSearchStage(
                workspace: workspace,
                profile: profile,
                query: query,
                candidates: candidates,
                requestSeedCandidates: requestSeedCandidates,
                searchRunId: searchRunId,
              );
            }
          }

          if (needsAdultCandidates) {
            progressToast.update('Adding adult-content candidates...');
            final adultCandidates = await workspace.service
                .fetchRecommendationCandidates(includeAdult: true);
            baseCandidates = _dedupeCandidates([
              ...baseCandidates,
              ...adultCandidates,
            ]);
            candidates = _dedupeCandidates([...candidates, ...adultCandidates]);
            if (candidates.isNotEmpty) {
              _publishRecommendationSearchStage(
                workspace: workspace,
                profile: profile,
                query: query,
                candidates: candidates,
                requestSeedCandidates: requestSeedCandidates,
                searchRunId: searchRunId,
              );
            }
          }

          if (query.isActive && !preferAiDiscoveryFirst) {
            progressToast.update(
              'Asking AI for known ${workspace.service.displayName} matches...',
            );
            final preliminaryRecommendations = _tasteEngine.rankCandidates(
              profile,
              candidates,
              query: query,
            );
            final aiDiscovered = await _discoverAiSuggestedItems(
              service: workspace.service,
              profile: profile,
              knownRecommendations: preliminaryRecommendations,
              query: query,
            );
            _logAiDiscoveryResults(
              aiLog,
              workspace.service.displayName,
              aiDiscovered,
            );
            if (aiDiscovered.isNotEmpty) {
              requestSeedCandidates = _dedupeCandidates([
                ...requestSeedCandidates,
                ...aiDiscovered,
              ]);
              candidates = _dedupeCandidates([...aiDiscovered, ...candidates]);
              _publishRecommendationSearchStage(
                workspace: workspace,
                profile: profile,
                query: query,
                candidates: candidates,
                requestSeedCandidates: requestSeedCandidates,
                searchRunId: searchRunId,
              );
            }
          }

          progressToast.update('Ranking matches against your profile...');
          final recommendations = _rankCandidatesForDisplay(
            workspace.service,
            profile,
            candidates,
            query: query,
            requestSeedCandidates: requestSeedCandidates,
          );
          _logRankedRecommendations(aiLog, recommendations);
          progressToast.update('Choosing the lead recommendation...');
          final selection = await _withChosenTopRecommendation(
            workspace.service,
            profile,
            recommendations,
            query,
          );
          if (selection.recommendations.isNotEmpty) {
            _logFinalSelection(aiLog, selection.recommendations.first);
          }
          final orderedRecommendations = selection.recommendations;
          if (selection.discoveredItem != null) {
            candidates = _dedupeCandidates([
              ...candidates,
              selection.discoveredItem!,
            ]);
          }

          if (!mounted ||
              workspace.activeRecommendationSearchRunId != searchRunId) {
            return;
          }
          setState(() {
            workspace.query = _storedQueryAfterInterpretation(
              query,
              workspace.service,
            );
            workspace.baseCandidates = baseCandidates;
            workspace.candidates = candidates;
            workspace.recommendations = orderedRecommendations;
            workspace.adultCandidatesLoaded =
                workspace.adultCandidatesLoaded || needsAdultCandidates;
            workspace.isRefreshingRecommendations = false;
            workspace.activeRecommendationSearchRunId = null;
          });
          unawaited(_persistWorkspace(workspace));
          _rebuildHomeRecommendationsSync();
        },
        zoneValues: {
          localAiConsoleLogZoneKey: aiLog,
          manualAiRequestHandlerZoneKey: _handleManualAiRequest,
        },
      );
    } catch (error) {
      if (!mounted ||
          workspace.activeRecommendationSearchRunId != searchRunId) {
        return;
      }
      setState(() {
        workspace.error = error.toString();
        workspace.isRefreshingRecommendations = false;
        workspace.activeRecommendationSearchRunId = null;
      });
      showErrorToast(context, 'Could not refresh recommendations: $error');
    } finally {
      if (_activeRecommendationProgressToast == progressToast) {
        _activeRecommendationProgressToast = null;
      }
      progressToast.dismiss();
    }
  }

  Future<void> _updateHomeRecommendationQuery(
    RecommendationQuery rawQuery,
  ) async {
    final allowExplicitContent = await _allowsExplicitContent();
    final homeRequestQuery = rawQuery.copyWith(
      includeAdult: false,
      excludeAdult: !allowExplicitContent,
    );
    if (!mounted) return;
    final importedWorkspaces = _importedWorkspaces;
    if (importedWorkspaces.isEmpty) {
      setState(() => _homeQuery = homeRequestQuery);
      return;
    }
    final searchRunId = ++_nextSearchRunId;

    setState(() {
      _homeQuery = homeRequestQuery;
      _isRefreshingHome = true;
      _homeError = null;
      _activeHomeSearchRunId = searchRunId;
    });
    final aiLog = AiConsoleLog();
    final progressToast = showProgressToast(
      context,
      'Reading your Home search across services...',
      consoleLog: aiLog,
    );
    _activeHomeProgressToast = progressToast;

    try {
      await runZoned(
        () async {
          final byService = <String, List<Recommendation>>{};
          final merged = <Recommendation>[];
          var chooserQuery = homeRequestQuery;

          for (final workspace in importedWorkspaces) {
            final profile = workspace.profile;
            if (profile == null) continue;
            final serviceRequestQuery = rawQuery.copyWith(
              includeAdult: false,
              excludeAdult:
                  workspace.service.supportsAdultContent &&
                  !allowExplicitContent,
            );
            progressToast.update(
              'Interpreting ${workspace.service.displayName} filters...',
            );
            final query = await _aiService.interpretRecommendationRequest(
              serviceRequestQuery,
              availableTags: _availableTagsFor(workspace),
              serviceName: workspace.service.displayName,
              allowedMediaTypes: workspace.service.supportedMediaTypes,
              allowedFormats: workspace.service.supportedFormats,
            );
            aiLog.addUserLine(
              '${workspace.service.displayName}: ${_searchSummaryForLog(query)}',
            );
            chooserQuery = chooserQuery.copyWith(
              aiSelectedTags: {
                ...chooserQuery.aiSelectedTags,
                ...query.aiSelectedTags,
              },
              mediaTypes: {...chooserQuery.mediaTypes, ...query.mediaTypes},
              formats: {...chooserQuery.formats, ...query.formats},
              includeAdult: chooserQuery.includeAdult || query.includeAdult,
              excludeAdult: chooserQuery.excludeAdult || query.excludeAdult,
            );

            var baseCandidates = workspace.baseCandidates;
            var candidates = query.isActive
                ? <MediaItem>[]
                : [...baseCandidates];
            final needsAdultCandidates =
                query.allowsAdult && !workspace.adultCandidatesLoaded;
            final preferAiDiscoveryFirst =
                query.isActive && _prefersAiDiscoveryFirst(workspace.service);

            if (preferAiDiscoveryFirst) {
              progressToast.update(
                'Asking AI for likely ${workspace.service.displayName} matches...',
              );
              final aiDiscovered = await _discoverAiSuggestedItems(
                service: workspace.service,
                profile: profile,
                knownRecommendations: const [],
                query: query,
              );
              if (aiDiscovered.isNotEmpty) {
                candidates = _dedupeCandidates([
                  ...aiDiscovered,
                  ...candidates,
                ]);
              }
            }

            if (query.isActive && candidates.isEmpty) {
              progressToast.update(
                'Searching ${workspace.service.displayName} candidates...',
              );
              final searchedCandidates = await workspace.service
                  .searchRecommendationCandidates(query);
              candidates = _dedupeCandidates([
                ...searchedCandidates,
                ...candidates,
              ]);
            }

            if (needsAdultCandidates) {
              progressToast.update(
                'Adding ${workspace.service.displayName} adult-content candidates...',
              );
              final adultCandidates = await workspace.service
                  .fetchRecommendationCandidates(includeAdult: true);
              baseCandidates = _dedupeCandidates([
                ...baseCandidates,
                ...adultCandidates,
              ]);
              candidates = _dedupeCandidates([
                ...candidates,
                ...adultCandidates,
              ]);
            }

            if (query.isActive && !preferAiDiscoveryFirst) {
              progressToast.update(
                'Asking AI for known ${workspace.service.displayName} matches...',
              );
              final preliminaryRecommendations = _tasteEngine.rankCandidates(
                profile,
                candidates,
                query: query,
              );
              final aiDiscovered = await _discoverAiSuggestedItems(
                service: workspace.service,
                profile: profile,
                knownRecommendations: preliminaryRecommendations,
                query: query,
              );
              if (aiDiscovered.isNotEmpty) {
                candidates = _dedupeCandidates([
                  ...aiDiscovered,
                  ...candidates,
                ]);
              }
            }

            progressToast.update(
              'Ranking ${workspace.service.displayName} matches...',
            );
            final recommendations = _tasteEngine.rankCandidates(
              profile,
              candidates,
              query: query,
            );
            if (recommendations.isEmpty) continue;

            workspace.baseCandidates = baseCandidates;
            workspace.candidates = candidates;
            workspace.adultCandidatesLoaded =
                workspace.adultCandidatesLoaded || needsAdultCandidates;
            unawaited(_persistWorkspace(workspace));

            byService[workspace.service.id] = recommendations;
            merged.addAll(recommendations);
          }

          merged.sort((a, b) => b.matchScore.compareTo(a.matchScore));
          progressToast.update('Choosing the best Home recommendation...');
          final profiles = importedWorkspaces
              .map((workspace) => workspace.profile!)
              .toList();
          final suggestion = await _aiService.suggestHomeRecommendation(
            profiles,
            merged,
            query: chooserQuery,
          );
          Recommendation? chosen;
          if (suggestion != null) {
            final targetWorkspace = _workspaceForSuggestedService(
              importedWorkspaces,
              suggestion.serviceName,
            );
            final targetProfile = targetWorkspace?.profile;
            if (targetWorkspace != null && targetProfile != null) {
              final resolved = await _resolveDirectSuggestion(
                service: targetWorkspace.service,
                profile: targetProfile,
                knownRecommendations:
                    byService[targetWorkspace.service.id] ?? const [],
                query: chooserQuery,
                suggestion: suggestion,
              );
              chosen = resolved.recommendation;
              if (chosen != null) {
                final directChosen = chosen;
                final serviceRecommendations = <Recommendation>[
                  directChosen,
                  for (final recommendation
                      in byService[targetWorkspace.service.id] ??
                          const <Recommendation>[])
                    if (recommendation.item.id != directChosen.item.id)
                      recommendation,
                ];
                byService[targetWorkspace.service.id] = serviceRecommendations;
                merged.removeWhere(
                  (recommendation) =>
                      recommendation.item.id == directChosen.item.id,
                );
                merged.add(directChosen);
                if (resolved.discoveredItem != null) {
                  targetWorkspace.candidates = _dedupeCandidates([
                    ...targetWorkspace.candidates,
                    resolved.discoveredItem!,
                  ]);
                  unawaited(_persistWorkspace(targetWorkspace));
                }
              }
            }
          }
          chosen ??= await _aiService.chooseHomeRecommendation(
            profiles,
            merged,
            query: chooserQuery,
          );
          final ordered = _promoteChosenRecommendation(merged, chosen);

          if (!mounted || _activeHomeSearchRunId != searchRunId) return;
          setState(() {
            _homeQuery = homeRequestQuery;
            _homeRecommendationsByService = byService;
            _homeRecommendations = ordered;
            _isRefreshingHome = false;
            _activeHomeSearchRunId = null;
          });
        },
        zoneValues: {
          localAiConsoleLogZoneKey: aiLog,
          manualAiRequestHandlerZoneKey: _handleManualAiRequest,
        },
      );
    } catch (error) {
      if (!mounted || _activeHomeSearchRunId != searchRunId) return;
      setState(() {
        _homeError = error.toString();
        _isRefreshingHome = false;
        _activeHomeSearchRunId = null;
      });
      showErrorToast(context, 'Could not refresh Home: $error');
    } finally {
      if (_activeHomeProgressToast == progressToast) {
        _activeHomeProgressToast = null;
      }
      progressToast.dismiss();
    }
  }

  void _logQueryInterpretation(AiConsoleLog log, RecommendationQuery query) {
    final original = query.request.trim();
    final interpreted = query.searchRequest.trim();
    final tags = query.aiSelectedTags.take(_visibleAiTagCount).toList();
    final formats = query.formats.map(_humanizeQueryFormat).toList();

    if (original.isNotEmpty &&
        interpreted.isNotEmpty &&
        original != interpreted) {
      log.addUserLine('You asked for: "$original"');
      log.addUserLine('I searched for: "$interpreted"');
    } else if (interpreted.isNotEmpty) {
      log.addUserLine('I searched for: "$interpreted"');
    } else if (original.isNotEmpty) {
      log.addUserLine('You asked for: "$original"');
    }

    if (formats.isNotEmpty) {
      log.addUserLine('Active filters: ${formats.join(', ')}');
    }
    if (tags.isNotEmpty) {
      log.addUserLine('I added these tags: ${tags.join(', ')}');
    }
    if (formats.isEmpty && tags.isEmpty) {
      log.addUserLine('I did not add any extra tags or filters.');
    }
  }

  void _logCandidateResults(
    AiConsoleLog log,
    String serviceName,
    List<MediaItem> items, {
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      log.addUserLine(emptyMessage);
      return;
    }
    log.addUserLine(
      '$serviceName search found ${items.length} likely matches: ${_summarizeTitles(items)}',
    );
  }

  void _logAiDiscoveryResults(
    AiConsoleLog log,
    String serviceName,
    List<MediaItem> items, {
    bool usedAsPrimarySearch = false,
  }) {
    if (items.isEmpty) {
      log.addUserLine(
        usedAsPrimarySearch
            ? 'AI could not produce any verified $serviceName matches, so I fell back to direct $serviceName search.'
            : 'AI did not add any extra titles beyond the direct search.',
      );
      return;
    }
    log.addUserLine(
      usedAsPrimarySearch
          ? 'AI found likely $serviceName matches: ${_summarizeTitles(items)}'
          : 'AI added extra possible matches: ${_summarizeTitles(items)}',
    );
  }

  void _logRankedRecommendations(
    AiConsoleLog log,
    List<Recommendation> recommendations,
  ) {
    if (recommendations.isEmpty) {
      log.addUserLine('Ranking did not find any strong matches yet.');
      return;
    }
    final shortlist = recommendations
        .take(3)
        .map((recommendation) {
          final score = recommendation.matchScore.round();
          return '${recommendation.item.title} ($score)';
        })
        .join(', ');
    log.addUserLine('Top ranked matches: $shortlist');
  }

  void _logFinalSelection(AiConsoleLog log, Recommendation recommendation) {
    final source = recommendation.isAiPick
        ? 'AI chose the lead match'
        : 'Lead match';
    log.addUserLine(
      '$source: ${recommendation.item.title} (${recommendation.matchScore.round()})',
    );
    final reason = recommendation.reason.trim();
    if (reason.isNotEmpty) {
      log.addUserLine('Why it won: ${_condenseLogReason(reason)}');
    }
  }

  void _publishRecommendationSearchStage({
    required _ServiceWorkspace workspace,
    required TasteProfile profile,
    required RecommendationQuery query,
    required List<MediaItem> candidates,
    required List<MediaItem> requestSeedCandidates,
    required int searchRunId,
  }) {
    if (!mounted || workspace.activeRecommendationSearchRunId != searchRunId) {
      return;
    }
    final recommendations = _rankCandidatesForDisplay(
      workspace.service,
      profile,
      candidates,
      query: query,
      requestSeedCandidates: requestSeedCandidates,
    );
    setState(() {
      workspace.query = _storedQueryAfterInterpretation(
        query,
        workspace.service,
      );
      workspace.candidates = candidates;
      workspace.recommendations = recommendations;
      workspace.isRefreshingRecommendations = true;
    });
  }

  String _summarizeTitles(List<MediaItem> items, {int limit = 5}) {
    return items.take(limit).map((item) => item.title).join(', ');
  }

  String _condenseLogReason(String reason, {int maxLength = 180}) {
    final normalized = reason.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1).trimRight()}...';
  }

  bool _prefersAiDiscoveryFirst(MediaService service) {
    return service.displayName == 'Steam';
  }

  String _searchSummaryForLog(RecommendationQuery query) {
    final tags = query.aiSelectedTags.take(_visibleAiTagCount).join(', ');
    final formats = query.formats.map(_humanizeQueryFormat).join(', ');
    final searchText = query.searchRequest;
    final parts = <String>[];
    if (searchText.isNotEmpty) {
      parts.add('typed "${query.request.trim()}"');
      if (query.interpretedRequest.trim().isNotEmpty &&
          query.interpretedRequest.trim() != query.request.trim()) {
        parts.add('searching "$searchText"');
      }
    }
    if (formats.isNotEmpty) parts.add('filters $formats');
    if (tags.isNotEmpty) parts.add('AI tags $tags');
    return parts.isEmpty ? 'No AI filters applied.' : parts.join(' • ');
  }

  String _humanizeQueryFormat(String format) {
    return switch (format) {
      'SERIES' => 'series',
      'MOVIE' => 'movie',
      'MANGA' => 'manga',
      'BOOK' => 'book',
      'SINGLE_PLAYER' => 'single-player',
      'MULTIPLAYER' => 'multiplayer',
      'CO_OP' => 'co-op',
      'ONLINE_CO_OP' => 'online co-op',
      'CONTROLLER' => 'controller',
      'STEAM_DECK' => 'Steam Deck',
      _ => format.toLowerCase(),
    };
  }

  Future<String> _handleManualAiRequest(ManualAiRequest request) async {
    if (!mounted) {
      throw StateError('Manual AI prompt could not be shown.');
    }
    var responseText = '';
    final response = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Manual AI response'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Copy this prompt into ChatGPT or another AI, then paste the response here.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        request.prompt,
                        key: const ValueKey('manual-ai-prompt'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('manual-ai-response'),
                    onChanged: (value) => responseText = value,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'AI response',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: request.prompt));
                showInfoToast(context, 'Prompt copied.');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy prompt'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, responseText.trim()),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Use response'),
            ),
          ],
        );
      },
    );
    if (response == null || response.trim().isEmpty) {
      throw StateError('Manual AI response was empty.');
    }
    return response.trim();
  }

  void _cancelRecommendationSearch() {
    final workspace = _activeWorkspace;
    if (!workspace.isRefreshingRecommendations) return;
    setState(() {
      workspace.activeRecommendationSearchRunId = null;
      workspace.isRefreshingRecommendations = false;
    });
    _activeRecommendationProgressToast?.dismiss();
    _activeRecommendationProgressToast = null;
    showInfoToast(context, 'Recommendation search canceled.');
  }

  void _cancelHomeSearch() {
    if (!_isRefreshingHome) return;
    setState(() {
      _activeHomeSearchRunId = null;
      _isRefreshingHome = false;
    });
    _activeHomeProgressToast?.dismiss();
    _activeHomeProgressToast = null;
    showInfoToast(context, 'Home search canceled.');
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

  Future<({List<Recommendation> recommendations, MediaItem? discoveredItem})>
  _withChosenTopRecommendation(
    MediaService service,
    TasteProfile profile,
    List<Recommendation> recommendations,
    RecommendationQuery query,
  ) async {
    final suggestion = await _aiService.suggestRecommendation(
      profile,
      recommendations,
      query: query,
    );
    if (suggestion != null) {
      final resolved = await _resolveDirectSuggestion(
        service: service,
        profile: profile,
        knownRecommendations: recommendations,
        query: query,
        suggestion: suggestion,
      );
      final direct = resolved.recommendation;
      if (direct != null) {
        return (
          recommendations: [
            direct.copyWith(isTopPick: true),
            for (final recommendation in recommendations)
              if (recommendation.item.id != direct.item.id)
                recommendation.copyWith(isTopPick: false),
          ],
          discoveredItem: resolved.discoveredItem,
        );
      }
    }

    if (recommendations.isEmpty) {
      return (recommendations: recommendations, discoveredItem: null);
    }

    if (_shouldKeepRankedTopPick(query, recommendations)) {
      final top = recommendations.first;
      return (
        recommendations: [
          top.copyWith(isTopPick: true),
          for (final recommendation in recommendations.skip(1))
            recommendation.copyWith(isTopPick: false),
        ],
        discoveredItem: null,
      );
    }

    final chosen = await _aiService.chooseTopRecommendation(
      profile,
      recommendations,
      query: query,
    );
    if (chosen == null) {
      return (recommendations: recommendations, discoveredItem: null);
    }

    return (
      recommendations: [
        chosen.copyWith(isTopPick: true),
        for (final recommendation in recommendations)
          if (recommendation.item.id != chosen.item.id)
            recommendation.copyWith(isTopPick: false),
      ],
      discoveredItem: null,
    );
  }

  List<Recommendation> _rankCandidatesForDisplay(
    MediaService service,
    TasteProfile profile,
    List<MediaItem> candidates, {
    required RecommendationQuery query,
    Iterable<MediaItem> requestSeedCandidates = const [],
  }) {
    final ranked = _tasteEngine.rankCandidates(
      profile,
      candidates,
      query: query,
    );
    final requestSeedRanked = _trustedRequestRecommendations(
      service,
      profile,
      query,
      requestSeedCandidates,
    );
    if (requestSeedRanked.isEmpty) return ranked;
    if (ranked.isEmpty) return requestSeedRanked;
    return _mergeRankedRecommendations([...ranked, ...requestSeedRanked]);
  }

  List<Recommendation> _trustedRequestRecommendations(
    MediaService service,
    TasteProfile profile,
    RecommendationQuery query,
    Iterable<MediaItem> candidates,
  ) {
    final seedCandidates = _dedupeCandidates(candidates.toList());
    if (seedCandidates.isEmpty) return const [];
    final relaxed = _tasteEngine.rankCandidates(
      profile,
      seedCandidates,
      query: _aiDiscoveryValidationQueryFor(service, query),
    );
    final byId = {
      for (final recommendation in relaxed)
        recommendation.item.id: recommendation,
    };
    final trusted = <Recommendation>[];
    for (final (index, item) in seedCandidates.indexed) {
      final recommendation = byId[item.id];
      if (recommendation == null) continue;
      final requestFitScore = max(58.0, 88.0 - index * 4.0);
      trusted.add(
        recommendation.copyWith(
          matchScore: max(recommendation.matchScore, requestFitScore),
          reason:
              'Found as a likely title match for "${query.request.trim()}"; ranked with your ${profile.serviceName} profile.',
          signals: _uniqueStrings(['request match', ...recommendation.signals]),
          isTopPick: false,
        ),
      );
    }
    return trusted;
  }

  List<Recommendation> _mergeRankedRecommendations(
    Iterable<Recommendation> recommendations,
  ) {
    final byId = <String, Recommendation>{};
    for (final recommendation in recommendations) {
      final existing = byId[recommendation.item.id];
      if (existing == null ||
          recommendation.matchScore > existing.matchScore ||
          (recommendation.isAiPick && !existing.isAiPick)) {
        byId[recommendation.item.id] = recommendation.copyWith(
          isTopPick: false,
        );
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
    if (merged.isEmpty) return merged;
    return [
      merged.first.copyWith(isTopPick: true),
      for (final recommendation in merged.skip(1))
        recommendation.copyWith(isTopPick: false),
    ];
  }

  List<String> _uniqueStrings(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
    ];
  }

  _ServiceWorkspace? _workspaceForSuggestedService(
    Iterable<_ServiceWorkspace> workspaces,
    String serviceName,
  ) {
    final target = _normalizedTitle(serviceName);
    for (final workspace in workspaces) {
      if (_normalizedTitle(workspace.service.displayName) == target ||
          _normalizedTitle(workspace.service.id) == target) {
        return workspace;
      }
    }
    return null;
  }

  Future<List<MediaItem>> _discoverAiSuggestedItems({
    required MediaService service,
    required TasteProfile profile,
    required List<Recommendation> knownRecommendations,
    required RecommendationQuery query,
  }) async {
    final suggestions = await _aiService.suggestRecommendationCandidates(
      profile,
      knownRecommendations,
      query: query,
      limit: 10,
    );
    if (suggestions.isEmpty) return const [];

    final matchingSuggestions = [
      for (final suggestion in suggestions)
        if (_normalizedTitle(suggestion.serviceName) ==
            _normalizedTitle(profile.serviceName))
          suggestion,
    ];
    final discovered = await Future.wait([
      for (final suggestion in matchingSuggestions)
        _resolveSuggestedItem(
          service: service,
          profile: profile,
          query: query,
          suggestion: suggestion,
        ),
    ]);
    return _dedupeCandidates(discovered.whereType<MediaItem>().toList());
  }

  bool _shouldKeepRankedTopPick(
    RecommendationQuery query,
    List<Recommendation> recommendations,
  ) {
    if (!query.isActive || recommendations.isEmpty) return false;
    final top = recommendations.first.matchScore;
    final next = recommendations.length > 1 ? recommendations[1].matchScore : 0;
    return top >= 95 && (top - next) >= 8;
  }

  bool _shouldSearchServiceCandidates(
    MediaService service, {
    required RecommendationQuery query,
    required List<MediaItem> candidates,
    required bool preferAiDiscoveryFirst,
  }) {
    if (!query.isActive) return false;
    if (candidates.isEmpty) return true;
    if (!preferAiDiscoveryFirst) return false;
    return service.displayName == 'Steam';
  }

  Future<MediaItem?> _resolveSuggestedItem({
    required MediaService service,
    required TasteProfile profile,
    required RecommendationQuery query,
    required AiRecommendationSuggestion suggestion,
  }) async {
    final titleKey = _normalizedTitle(suggestion.title);
    if (titleKey.isEmpty) return null;

    final searchResults = await service.searchRecommendationCandidates(
      RecommendationQuery(
        request: suggestion.title,
        includeAdult: query.allowsAdult,
        excludeAdult: query.excludeAdult,
      ),
    );
    MediaItem? item;
    for (final result in searchResults) {
      if (_itemTitleKeys(result).contains(titleKey)) {
        item = result;
        break;
      }
    }
    if (item == null) return null;

    final resolvedItem = item;
    if (profile.library.any(
      (owned) =>
          owned.id == resolvedItem.id ||
          _itemTitleKeys(owned).any(_itemTitleKeys(resolvedItem).contains),
    )) {
      return null;
    }

    final requiredMediaTypes = query.effectiveMediaTypes();
    if (requiredMediaTypes.isNotEmpty &&
        !requiredMediaTypes.contains(resolvedItem.mediaType)) {
      return null;
    }
    if (resolvedItem.isAdult && !query.allowsAdult) return null;

    final validated = _tasteEngine.rankCandidates(profile, [
      resolvedItem,
    ], query: _aiDiscoveryValidationQueryFor(service, query));
    return validated.isEmpty ? null : resolvedItem;
  }

  RecommendationQuery _aiDiscoveryValidationQueryFor(
    MediaService service,
    RecommendationQuery query,
  ) {
    final applicableFormats = query
        .effectiveFormats()
        .where(service.supportedFormats.contains)
        .toSet();
    final applicableMediaTypes = query
        .effectiveMediaTypes()
        .where(service.supportedMediaTypes.contains)
        .toSet();
    return RecommendationQuery(
      request: '',
      interpretedRequest: '',
      selectedTags: query.selectedTags,
      aiSelectedTags: query.aiSelectedTags,
      includeAdult: query.allowsAdult,
      excludeAdult: query.excludeAdult,
      mediaTypes: applicableMediaTypes,
      formats: applicableFormats,
    );
  }

  Future<({Recommendation? recommendation, MediaItem? discoveredItem})>
  _resolveDirectSuggestion({
    required MediaService service,
    required TasteProfile profile,
    required List<Recommendation> knownRecommendations,
    required RecommendationQuery query,
    required AiRecommendationSuggestion suggestion,
  }) async {
    final titleKey = _normalizedTitle(suggestion.title);
    if (titleKey.isEmpty) {
      return (recommendation: null, discoveredItem: null);
    }

    for (final recommendation in knownRecommendations) {
      if (_itemTitleKeys(recommendation.item).contains(titleKey)) {
        return (
          recommendation: recommendation.copyWith(
            reason: suggestion.reason,
            isAiPick: true,
          ),
          discoveredItem: null,
        );
      }
    }

    try {
      final item = await _resolveSuggestedItem(
        service: service,
        profile: profile,
        query: query,
        suggestion: suggestion,
      );
      if (item == null) {
        return (recommendation: null, discoveredItem: null);
      }
      final validated = _tasteEngine.rankCandidates(profile, [
        item,
      ], query: _aiDiscoveryValidationQueryFor(service, query));
      if (validated.isEmpty) {
        return (recommendation: null, discoveredItem: null);
      }
      return (
        recommendation: validated.first.copyWith(
          reason: suggestion.reason,
          isAiPick: true,
        ),
        discoveredItem: item,
      );
    } catch (_) {
      return (recommendation: null, discoveredItem: null);
    }
  }

  String _normalizedTitle(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  Set<String> _itemTitleKeys(MediaItem item) {
    return {
      _normalizedTitle(item.title),
      for (final title in item.alternativeTitles) _normalizedTitle(title),
    }.where((title) => title.isNotEmpty).toSet();
  }

  Future<void> _loadSavedSessions() async {
    final sessions = await _profileStore.loadSessions();
    if (!mounted || sessions.isEmpty) return;
    final allowExplicitContent = await _allowsExplicitContent();
    if (!mounted) return;

    setState(() {
      for (final entry in sessions.entries) {
        final workspace = _workspaces[entry.key];
        if (workspace == null) continue;
        final session = entry.value;
        workspace.restore(
          session.copyWith(
            query: session.query.copyWith(
              includeAdult: false,
              excludeAdult:
                  workspace.service.supportsAdultContent &&
                  !allowExplicitContent,
            ),
          ),
          tasteEngine: _tasteEngine,
        );
      }
      final activeWorkspace = _activeWorkspace;
      _userNameController.text = activeWorkspace.userNameDraft.isNotEmpty
          ? activeWorkspace.userNameDraft
          : activeWorkspace.profile?.userName ?? '';
    });
    _rebuildHomeRecommendationsSync();
  }

  Future<bool> _allowsExplicitContent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(LocalAiSettingsKeys.allowExplicitContent) ?? false;
  }

  Future<void> _persistWorkspace(_ServiceWorkspace workspace) async {
    final session = workspace.toLocalSession();
    if (session == null) return;
    await _profileStore.saveSession(session);
  }

  void _rebuildHomeRecommendationsSync() {
    final byService = <String, List<Recommendation>>{};
    final merged = <Recommendation>[];
    for (final workspace in _importedWorkspaces) {
      final recommendations = workspace.recommendations;
      if (recommendations.isEmpty) continue;
      byService[workspace.service.id] = recommendations;
      merged.addAll(recommendations);
    }
    merged.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    final ordered = _promoteChosenRecommendation(
      merged,
      merged.isEmpty ? null : merged.first,
    );
    if (!mounted) return;
    setState(() {
      _homeRecommendationsByService = byService;
      _homeRecommendations = ordered;
    });
  }

  List<Recommendation> _promoteChosenRecommendation(
    List<Recommendation> recommendations,
    Recommendation? chosen,
  ) {
    if (recommendations.isEmpty) return recommendations;
    final top = chosen ?? recommendations.first;
    return [
      top.copyWith(isTopPick: true),
      for (final recommendation in recommendations)
        if (recommendation.item.id != top.item.id)
          recommendation.copyWith(isTopPick: false),
    ];
  }

  Future<void> _openRecommendationChat() async {
    final key = _activeSurface == _ActiveSurface.home
        ? 'home'
        : 'service:${_mediaService.id}';
    final messages = _chatMessagesBySurface.putIfAbsent(key, () => []);
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final sheet = _RecommendationChatSheet(
      initialMessages: messages,
      onSend: (text) => _sendChatMessage(key, text),
      onAction: (action) => _runChatAction(key, action),
    );

    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            alignment: Alignment.centerRight,
            insetPadding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            backgroundColor: Colors.transparent,
            child: SizedBox(width: 430, child: sheet),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.42,
          maxChildSize: 0.96,
          expand: false,
          builder: (context, scrollController) {
            return _RecommendationChatSheet(
              initialMessages: messages,
              scrollController: scrollController,
              onSend: (text) => _sendChatMessage(key, text),
              onAction: (action) => _runChatAction(key, action),
            );
          },
        );
      },
    );
  }

  Future<AiChatResponse> _sendChatMessage(String key, String text) async {
    final messages = _chatMessagesBySurface.putIfAbsent(key, () => []);
    messages.add(AiChatMessage(role: AiChatRole.user, text: text));
    final aiLog = AiConsoleLog();
    try {
      final response = await runZoned(
        () => _aiService.chatAboutRecommendations(_chatRequestFor(messages)),
        zoneValues: {
          localAiConsoleLogZoneKey: aiLog,
          manualAiRequestHandlerZoneKey: _handleManualAiRequest,
        },
      );
      messages.add(
        AiChatMessage(role: AiChatRole.assistant, text: response.message),
      );
      return response;
    } catch (error) {
      final response = AiChatResponse(message: 'I could not answer: $error');
      messages.add(
        AiChatMessage(role: AiChatRole.assistant, text: response.message),
      );
      return response;
    }
  }

  AiChatRequest _chatRequestFor(List<AiChatMessage> messages) {
    if (_activeSurface == _ActiveSurface.home) {
      final imported = _importedWorkspaces;
      return AiChatRequest(
        surface: AiChatSurface.home,
        serviceName: 'Home',
        profiles: [
          for (final workspace in imported)
            if (workspace.profile != null) workspace.profile!,
        ],
        query: _homeQuery,
        recommendations: _homeRecommendations,
        recommendationsByService: _homeRecommendationsByService,
        messages: List.unmodifiable(messages),
        availableTags: {
          for (final workspace in imported) ..._availableTagsFor(workspace),
        }.toList(),
        availableServices: _mediaServices
            .map((service) => service.displayName)
            .toList(),
      );
    }

    final workspace = _activeWorkspace;
    return AiChatRequest(
      surface: AiChatSurface.service,
      serviceName: workspace.service.displayName,
      profiles: [if (workspace.profile != null) workspace.profile!],
      query: workspace.query,
      recommendations: workspace.recommendations,
      recommendationsByService: {
        workspace.service.id: workspace.recommendations,
      },
      messages: List.unmodifiable(messages),
      availableTags: _availableTagsFor(workspace),
      availableServices: [workspace.service.displayName],
    );
  }

  Future<String> _runChatAction(String key, AiChatAction action) async {
    switch (action.type) {
      case AiChatActionType.applyQuery:
        final query = action.query;
        if (query == null) return 'No search change was provided.';
        setState(() {
          if (_activeSurface == _ActiveSurface.home) {
            _homeQuery = query;
          } else {
            _activeWorkspace.query = query;
          }
        });
        return 'Search controls updated. Run the search when you are ready.';
      case AiChatActionType.runSearch:
      case AiChatActionType.discoverCandidates:
        final query = action.query;
        if (query == null) return 'No search query was provided.';
        if (_activeSurface == _ActiveSurface.home) {
          await _updateHomeRecommendationQuery(query);
        } else {
          await _updateRecommendationQuery(query);
        }
        return action.type == AiChatActionType.discoverCandidates
            ? 'I searched for fresh candidates and refreshed the list.'
            : 'Search complete.';
      case AiChatActionType.explainRecommendation:
        final recommendation = _recommendationById(action.recommendationId);
        final profile = _profileForRecommendation(recommendation);
        if (recommendation == null || profile == null) {
          return 'I could not find that recommendation anymore.';
        }
        final explanation = await runZoned(
          () => _aiService.explainRecommendation(profile, recommendation),
          zoneValues: {manualAiRequestHandlerZoneKey: _handleManualAiRequest},
        );
        _chatMessagesBySurface[key]?.add(
          AiChatMessage(role: AiChatRole.assistant, text: explanation),
        );
        return explanation;
      case AiChatActionType.backgroundPrompt:
        final prompt = action.prompt?.trim();
        if (prompt == null || prompt.isEmpty) {
          return 'No background prompt was provided.';
        }
        final response = await _sendChatMessage(key, prompt);
        return response.message;
    }
  }

  Recommendation? _recommendationById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final recommendation in [
      ..._homeRecommendations,
      ..._activeWorkspace.recommendations,
    ]) {
      if (recommendation.item.id == id) return recommendation;
    }
    return null;
  }

  TasteProfile? _profileForRecommendation(Recommendation? recommendation) {
    if (recommendation == null) return null;
    for (final workspace in _importedWorkspaces) {
      final profile = workspace.profile;
      if (profile == null) continue;
      if (workspace.service.displayName == recommendation.item.serviceLabel ||
          workspace.service.id == recommendation.item.sourceId ||
          workspace.recommendations.any(
            (entry) => entry.item.id == recommendation.item.id,
          )) {
        return profile;
      }
    }
    return _activeWorkspace.profile;
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
              final workspace = _activeWorkspace;
              final shell = _activeSurface == _ActiveSurface.home
                  ? _HomeContentShell(
                      isMobileSurface: !isDesktop,
                      services: _mediaServices,
                      workspaces: _workspaces,
                      query: _homeQuery,
                      recommendations: _homeRecommendations,
                      recommendationsByService: _homeRecommendationsByService,
                      isRefreshing: _isRefreshingHome,
                      error: _homeError,
                      aiService: _aiService,
                      onQueryChanged: _updateHomeRecommendationQuery,
                      onCancelSearch: _cancelHomeSearch,
                      onConnectService: _selectService,
                      onChatTap: _openRecommendationChat,
                    )
                  : _ContentShell(
                      isMobileSurface: !isDesktop,
                      profile: workspace.profile,
                      recommendations: workspace.recommendations,
                      isLoading: workspace.isLoading,
                      error: workspace.error,
                      aiService: _aiService,
                      userNameController: _userNameController,
                      mediaService: workspace.service,
                      onImport: _importProfile,
                      onSignOut: _signOut,
                      onSwitchUser: _switchUser,
                      query: workspace.query,
                      isRefreshingRecommendations:
                          workspace.isRefreshingRecommendations,
                      availableTags: _availableTags,
                      onQueryChanged: _updateRecommendationQuery,
                      onCancelSearch: _cancelRecommendationSearch,
                      onChatTap: _openRecommendationChat,
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
                        isHomeActive: _activeSurface == _ActiveSurface.home,
                        onHomeTap: _selectHome,
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
                isHomeActive: _activeSurface == _ActiveSurface.home,
                onHomeTap: _selectHome,
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
    return _availableTagsFor(_activeWorkspace);
  }

  List<String> _availableTagsFor(_ServiceWorkspace workspace) {
    final counts = <String, int>{};
    for (final tag in workspace.profile?.favoriteGenres ?? const <String>[]) {
      counts.update(tag, (count) => count + 4, ifAbsent: () => 4);
    }
    for (final item in workspace.baseCandidates) {
      for (final tag in item.tags) {
        counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final baseTags = workspace.service.displayName == 'Steam'
        ? RecommendationQuery.steamBrowsableTags
        : RecommendationQuery.aniListBrowsableTags;
    return {
      ...baseTags,
      ...workspace.serviceTags,
      ...entries.map((entry) => entry.key),
    }.toList();
  }

  _ServiceWorkspace get _activeWorkspace => _workspaces[_mediaService.id]!;

  List<_ServiceWorkspace> get _importedWorkspaces {
    return [
      for (final service in _mediaServices)
        if (_workspaces[service.id]?.hasProfile ?? false)
          _workspaces[service.id]!,
    ];
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

class _HomeContentShell extends StatelessWidget {
  final bool isMobileSurface;
  final List<MediaService> services;
  final Map<String, _ServiceWorkspace> workspaces;
  final RecommendationQuery query;
  final List<Recommendation> recommendations;
  final Map<String, List<Recommendation>> recommendationsByService;
  final bool isRefreshing;
  final String? error;
  final LocalAiService aiService;
  final ValueChanged<RecommendationQuery> onQueryChanged;
  final VoidCallback onCancelSearch;
  final ValueChanged<MediaService> onConnectService;
  final VoidCallback onChatTap;

  const _HomeContentShell({
    required this.isMobileSurface,
    required this.services,
    required this.workspaces,
    required this.query,
    required this.recommendations,
    required this.recommendationsByService,
    required this.isRefreshing,
    required this.error,
    required this.aiService,
    required this.onQueryChanged,
    required this.onCancelSearch,
    required this.onConnectService,
    required this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(isMobileSurface ? 0 : 34);
    final shellPadding = isMobileSurface
        ? const EdgeInsets.fromLTRB(14, 16, 14, 0)
        : const EdgeInsets.fromLTRB(18, 18, 18, 0);
    final imported = [
      for (final service in services)
        if (workspaces[service.id]?.profile != null) workspaces[service.id]!,
    ];
    final missing = [
      for (final service in services)
        if (workspaces[service.id]?.profile == null) service,
    ];
    final readableInset = EdgeInsets.only(left: isMobileSurface ? 54 : 0);

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
                _HomeHeader(aiService: aiService, onChatTap: onChatTap),
                const SizedBox(height: 14),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: readableInset,
                          child: _HomeSearchPanel(
                            query: query,
                            isRefreshing: isRefreshing,
                            onQueryChanged: onQueryChanged,
                            onCancelSearch: onCancelSearch,
                          ),
                        ),
                      ),
                      if (error != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: readableInset.add(
                              const EdgeInsets.only(top: 12),
                            ),
                            child: Text(
                              error!,
                              style: const TextStyle(color: Color(0xFFFF9AA8)),
                            ),
                          ),
                        ),
                      if (imported.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: readableInset.add(
                              const EdgeInsets.only(top: 14),
                            ),
                            child: _HomeConnectGrid(
                              services: services,
                              onConnectService: onConnectService,
                            ),
                          ),
                        )
                      else ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: recommendations.isEmpty
                                ? Padding(
                                    padding: readableInset,
                                    child: _EmptyHomeRecommendations(
                                      query: query,
                                    ),
                                  )
                                : _TopRecommendationCard(
                                    recommendation: recommendations.first,
                                  ),
                          ),
                        ),
                        if (missing.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: readableInset.add(
                                const EdgeInsets.only(top: 14),
                              ),
                              child: _MissingServiceStrip(
                                services: missing,
                                onConnectService: onConnectService,
                              ),
                            ),
                          ),
                        for (final workspace in imported)
                          _HomeServiceSection(
                            workspace: workspace,
                            recommendations:
                                recommendationsByService[workspace
                                    .service
                                    .id] ??
                                workspace.recommendations,
                            readableInset: readableInset,
                          ),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 96)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isMobileSurface) return shell;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: shell,
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final LocalAiService aiService;
  final VoidCallback onChatTap;

  const _HomeHeader({required this.aiService, required this.onChatTap});

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
                'One local feed across your imported services.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.64),
                ),
              ),
            ],
          ),
        ),
        _AiChatPill(
          icon: Icons.auto_awesome_rounded,
          label: 'AI chat',
          onTap: onChatTap,
        ),
      ],
    );
  }
}

class _HomeSearchPanel extends StatefulWidget {
  final RecommendationQuery query;
  final bool isRefreshing;
  final ValueChanged<RecommendationQuery> onQueryChanged;
  final VoidCallback onCancelSearch;

  const _HomeSearchPanel({
    required this.query,
    required this.isRefreshing,
    required this.onQueryChanged,
    required this.onCancelSearch,
  });

  @override
  State<_HomeSearchPanel> createState() => _HomeSearchPanelState();
}

class _HomeSearchPanelState extends State<_HomeSearchPanel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query.request);
  }

  @override
  void didUpdateWidget(covariant _HomeSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query.request != widget.query.request &&
        widget.query.request != _controller.text) {
      _controller.text = widget.query.request;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final request = _controller.text.trim();
    final requestChanged = request != widget.query.request.trim();
    widget.onQueryChanged(
      widget.query.copyWith(
        request: request,
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('home-recommendation-query'),
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Ask for what you want next',
                prefixIcon: const Icon(Icons.auto_awesome_rounded),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: widget.isRefreshing
                ? 'Cancel Home search'
                : 'Search Home recommendations',
            onPressed: widget.isRefreshing ? widget.onCancelSearch : _submit,
            icon: widget.isRefreshing
                ? const Icon(Icons.close_rounded)
                : const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }
}

class _HomeConnectGrid extends StatelessWidget {
  final List<MediaService> services;
  final ValueChanged<MediaService> onConnectService;

  const _HomeConnectGrid({
    required this.services,
    required this.onConnectService,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final service in services)
              SizedBox(
                width: isNarrow ? constraints.maxWidth : 260,
                child: _HomeConnectCard(
                  service: service,
                  onConnect: () => onConnectService(service),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MissingServiceStrip extends StatelessWidget {
  final List<MediaService> services;
  final ValueChanged<MediaService> onConnectService;

  const _MissingServiceStrip({
    required this.services,
    required this.onConnectService,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final service in services)
          ActionChip(
            avatar: Icon(_serviceIcon(service), size: 18),
            label: Text('Connect ${service.displayName}'),
            onPressed: () => onConnectService(service),
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
      ],
    );
  }
}

class _HomeConnectCard extends StatelessWidget {
  final MediaService service;
  final VoidCallback onConnect;

  const _HomeConnectCard({required this.service, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_serviceIcon(service), color: Colors.white70),
          const SizedBox(height: 10),
          Text(
            service.connectTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            service.connectDescription,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.68),
              height: 1.32,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.login_rounded),
            label: Text(service.importButtonLabel),
          ),
        ],
      ),
    );
  }
}

class _HomeServiceSection extends StatelessWidget {
  final _ServiceWorkspace workspace;
  final List<Recommendation> recommendations;
  final EdgeInsets readableInset;

  const _HomeServiceSection({
    required this.workspace,
    required this.recommendations,
    required this.readableInset,
  });

  @override
  Widget build(BuildContext context) {
    final visible = recommendations.take(4).toList();
    if (visible.isEmpty) return const SliverToBoxAdapter(child: SizedBox());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: readableInset,
              child: Row(
                children: [
                  Icon(
                    _serviceIcon(workspace.service),
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    workspace.service.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (final recommendation in visible) ...[
              _RecommendationTile(recommendation: recommendation),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyHomeRecommendations extends StatelessWidget {
  final RecommendationQuery query;

  const _EmptyHomeRecommendations({required this.query});

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
                ? 'No cross-service matches for this request yet.'
                : 'Imported services are ready. Ask for a mood, format, or activity.',
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
  final VoidCallback onCancelSearch;
  final VoidCallback onChatTap;

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
    required this.onCancelSearch,
    required this.onChatTap,
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
                  onChatTap: onChatTap,
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
                            onCancelSearch: onCancelSearch,
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
  final bool isHomeActive;
  final VoidCallback onHomeTap;
  final ValueChanged<MediaService> onServiceTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onProfileTap;
  final ValueChanged<String> onUnavailableTap;

  const _MobileLiquidShell({
    required this.child,
    required this.services,
    required this.activeServiceId,
    required this.isHomeActive,
    required this.onHomeTap,
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
          top: 132,
          bottom: 16,
          left: 6,
          child: _MobileLiquidRail(
            services: services,
            activeServiceId: activeServiceId,
            isHomeActive: isHomeActive,
            onHomeTap: onHomeTap,
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
  final VoidCallback onChatTap;

  const _ShellHeader({
    required this.profile,
    required this.aiService,
    required this.serviceName,
    required this.onSignOut,
    required this.onSwitchUser,
    required this.onChatTap,
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
            _AiChatPill(
              icon: Icons.auto_awesome_rounded,
              label: 'AI chat',
              onTap: onChatTap,
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
  final VoidCallback onCancelSearch;

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
    required this.onCancelSearch,
  });

  @override
  Widget build(BuildContext context) {
    final topPick = recommendations.isEmpty ? null : recommendations.first;
    final otherPicks = recommendations.skip(1).toList();
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
                      onCancelSearch: onCancelSearch,
                    ),
                  ),
                  if (isRefreshing) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: readableInset,
                      child: _RecommendationLoadingStrip(
                        resultCount: recommendations.length,
                      ),
                    ),
                  ],
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
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _TopRecommendationCard(
                        key: ValueKey('top-${topPick.item.id}'),
                        recommendation: topPick,
                      ),
                    ),
                  if (otherPicks.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: readableInset,
                      child: Text(
                        query.isActive
                            ? 'More matching this request'
                            : 'More for this profile',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            if (otherPicks.isEmpty)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else
              SliverList.separated(
                itemBuilder: (context, index) {
                  final recommendation = otherPicks[index];
                  return TweenAnimationBuilder<double>(
                    key: ValueKey('ranked-${recommendation.item.id}'),
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 260 + index * 35),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: _RecommendationTile(recommendation: recommendation),
                  );
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

class _RecommendationLoadingStrip extends StatelessWidget {
  final int resultCount;

  const _RecommendationLoadingStrip({required this.resultCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = resultCount == 0
        ? 'Finding matches'
        : 'Sorting $resultCount ${resultCount == 1 ? 'match' : 'matches'}';

    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
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
  final VoidCallback onCancelSearch;

  const _RecommendationSearchPanel({
    required this.query,
    required this.isRefreshing,
    required this.availableTags,
    required this.mediaService,
    required this.onQueryChanged,
    required this.onCancelSearch,
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
    if (oldWidget.query.request != widget.query.request &&
        widget.query.request != _searchController.text) {
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
    final inferredForNextRequest = RecommendationQuery(
      request: nextRequest,
    ).withInferredSelections(widget.availableTags);
    final clearStaleServiceFormats = requestChanged;
    final nextFormats = clearStaleServiceFormats
        ? {
            for (final format in inferredForNextRequest.formats)
              if (widget.mediaService.supportedFormats.contains(format))
                RecommendationQuery.canonicalFormat(format),
          }
        : widget.query.formats;
    final nextMediaTypes =
        requestChanged && widget.mediaService.displayName == 'AniList'
        ? inferredForNextRequest.mediaTypes
        : widget.query.mediaTypes;
    widget.onQueryChanged(
      widget.query.copyWith(
        request: nextRequest,
        interpretedRequest: requestChanged
            ? ''
            : widget.query.interpretedRequest,
        aiSelectedTags: requestChanged
            ? <String>{}
            : widget.query.aiSelectedTags,
        formats: nextFormats,
        mediaTypes: nextMediaTypes,
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
                tooltip: widget.isRefreshing
                    ? 'Cancel recommendation search'
                    : 'Search recommendations',
                onPressed: widget.isRefreshing
                    ? widget.onCancelSearch
                    : _submitRequest,
                icon: widget.isRefreshing
                    ? const Icon(Icons.close_rounded)
                    : const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.mediaService.displayName != 'AniList') ...[
            _FilterSection(
              label: 'Type',
              children: [
                for (final mediaType in widget.mediaService.supportedMediaTypes)
                  _FilterChipButton(
                    key: ValueKey('filter-type-${mediaType.toLowerCase()}'),
                    label: _mediaTypeLabel(mediaType),
                    selected: widget.query.effectiveMediaTypes().contains(
                      mediaType,
                    ),
                    onSelected: () => _toggleMediaType(mediaType),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _FilterSection(
            label: widget.mediaService.displayName == 'Steam'
                ? 'Modes'
                : 'Format',
            children: widget.mediaService.supportedFormats.map((format) {
              return _FilterChipButton(
                key: ValueKey('filter-format-${format.toLowerCase()}'),
                label: _formatLabel(format),
                selected: widget.query.effectiveFormats().contains(format),
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
      'SERIES' => 'Series',
      'MOVIE' => 'Movie',
      'MANGA' => 'Manga',
      'BOOK' => 'Book',
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
      widget.query.copyWith(
        selectedTags: tags,
        aiSelectedTags: aiTags,
        interpretedRequest: '',
      ),
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
      widget.query.copyWith(
        selectedTags: selected,
        aiSelectedTags: {},
        interpretedRequest: '',
      ),
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
    widget.onQueryChanged(
      widget.query.copyWith(mediaTypes: mediaTypes, interpretedRequest: ''),
    );
  }

  void _toggleFormat(String format) {
    final formats = {
      for (final selected in widget.query.formats)
        RecommendationQuery.canonicalFormat(selected),
    };
    if (widget.mediaService.displayName == 'AniList') {
      if (formats.contains(format)) {
        formats.remove(format);
      } else {
        formats
          ..clear()
          ..add(format);
      }
    } else {
      formats.contains(format) ? formats.remove(format) : formats.add(format);
    }
    widget.onQueryChanged(
      widget.query.copyWith(
        interpretedRequest: '',
        formats: formats,
        mediaTypes: widget.mediaService.displayName == 'AniList'
            ? RecommendationQuery.aniListMediaTypesForFormats(formats)
            : widget.query.mediaTypes,
      ),
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
    final hiddenCount = max(0, activeTags.length - visibleTags.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                activeTags.isEmpty
                    ? 'Tags'
                    : 'Tags · ${selectedTags.length} pinned · ${aiSelectedTags.length} suggested',
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

  const _TopRecommendationCard({super.key, required this.recommendation});

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
          _recommendationSummary(
            recommendation,
            preferAiReason: recommendation.isAiPick,
          ),
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
                    _recommendationSummary(
                      recommendation,
                      preferAiReason: recommendation.isAiPick,
                    ),
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

String _recommendationSummary(
  Recommendation recommendation, {
  required bool preferAiReason,
}) {
  final reason = recommendation.reason.trim();
  if (preferAiReason && reason.isNotEmpty) return reason;

  final description = _cleanMediaDescription(recommendation.item.description);
  if (description.isNotEmpty) return description;
  return reason;
}

String _cleanMediaDescription(String? description) {
  if (description == null) return '';
  return description
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
  final bool isHomeActive;
  final VoidCallback onHomeTap;
  final ValueChanged<MediaService> onServiceTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onProfileTap;
  final ValueChanged<String> onUnavailableTap;

  const _MobileLiquidRail({
    required this.services,
    required this.activeServiceId,
    required this.isHomeActive,
    required this.onHomeTap,
    required this.onServiceTap,
    required this.onSettingsTap,
    required this.onProfileTap,
    required this.onUnavailableTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryPod = _LiquidGlassPod(
      borderRadius: BorderRadius.circular(26),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LiquidRailButton(
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: isHomeActive,
            onTap: onHomeTap,
          ),
          for (final service in services)
            _LiquidRailButton(
              icon: _serviceIcon(service),
              label: service.displayName,
              isActive: !isHomeActive && activeServiceId == service.id,
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
    );
    final secondaryPod = _LiquidGlassPod(
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
    );

    return SizedBox(
      key: const ValueKey('mobile-liquid-rail'),
      width: 50,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const compactRailHeight = 372.0;
          if (constraints.maxHeight < compactRailHeight) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  primaryPod,
                  const SizedBox(height: 10),
                  secondaryPod,
                ],
              ),
            );
          }

          return Column(children: [primaryPod, const Spacer(), secondaryPod]);
        },
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
  final bool isHomeActive;
  final VoidCallback onHomeTap;
  final ValueChanged<MediaService> onServiceTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onProfileTap;
  final ValueChanged<String> onUnavailableTap;

  const _ServiceDock({
    required this.isDesktop,
    required this.services,
    required this.activeServiceId,
    required this.isHomeActive,
    required this.onHomeTap,
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
        isActive: isHomeActive,
        onTap: onHomeTap,
      ),
      for (final service in services)
        _DockButton(
          icon: _serviceIcon(service),
          label: service.displayName,
          isActive: !isHomeActive && activeServiceId == service.id,
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

class _RecommendationChatSheet extends StatefulWidget {
  final List<AiChatMessage> initialMessages;
  final ScrollController? scrollController;
  final Future<AiChatResponse> Function(String text) onSend;
  final Future<String> Function(AiChatAction action) onAction;

  const _RecommendationChatSheet({
    required this.initialMessages,
    required this.onSend,
    required this.onAction,
    this.scrollController,
  });

  @override
  State<_RecommendationChatSheet> createState() =>
      _RecommendationChatSheetState();
}

class _RecommendationChatSheetState extends State<_RecommendationChatSheet> {
  late final TextEditingController _controller;
  late final ScrollController _scrollController;
  late List<AiChatMessage> _messages;
  List<AiChatAction> _actions = const [];
  bool _isWaiting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _scrollController = widget.scrollController ?? ScrollController();
    _messages = [...widget.initialMessages];
    if (_messages.isEmpty) {
      _messages = [
        AiChatMessage(
          role: AiChatRole.assistant,
          text:
              'Ask me about the current recommendations, or tell me how to refine the list.',
        ),
      ];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isWaiting) return;
    setState(() {
      _controller.clear();
      _error = null;
      _actions = const [];
      _isWaiting = true;
      _messages.add(AiChatMessage(role: AiChatRole.user, text: text));
    });
    _scrollSoon();
    try {
      final response = await widget.onSend(text);
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiChatMessage(role: AiChatRole.assistant, text: response.message),
        );
        _actions = response.actions;
        _isWaiting = false;
      });
      _scrollSoon();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isWaiting = false;
      });
    }
  }

  Future<void> _runAction(AiChatAction action) async {
    if (_isWaiting) return;
    setState(() {
      _error = null;
      _isWaiting = true;
    });
    try {
      final message = await widget.onAction(action);
      if (!mounted) return;
      setState(() {
        _messages.add(AiChatMessage(role: AiChatRole.assistant, text: message));
        _actions = const [];
        _isWaiting = false;
      });
      _scrollSoon();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isWaiting = false;
      });
    }
  }

  void _scrollSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: _GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFBDEECD),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI chat',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close AI chat',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('recommendation-chat-messages'),
                controller: _scrollController,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _ChatBubble(message: message);
                },
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemCount: _messages.length,
              ),
            ),
            if (_isWaiting) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF9AA8))),
            ],
            if (_actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in _actions)
                      ActionChip(
                        avatar: Icon(_chatActionIcon(action.type), size: 16),
                        label: Text(action.label),
                        onPressed: _isWaiting ? null : () => _runAction(action),
                        backgroundColor: Colors.white.withValues(alpha: 0.07),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('recommendation-chat-input'),
                    controller: _controller,
                    enabled: !_isWaiting,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Talk about these recommendations',
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Send chat message',
                  onPressed: _isWaiting ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final AiChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF89D6B3).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.86),
            height: 1.32,
          ),
        ),
      ),
    );
  }
}

IconData _chatActionIcon(AiChatActionType type) {
  return switch (type) {
    AiChatActionType.applyQuery => Icons.tune_rounded,
    AiChatActionType.runSearch => Icons.manage_search_rounded,
    AiChatActionType.discoverCandidates => Icons.travel_explore_rounded,
    AiChatActionType.explainRecommendation => Icons.psychology_alt_rounded,
    AiChatActionType.backgroundPrompt => Icons.hourglass_top_rounded,
  };
}

class _AiChatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AiChatPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open AI chat',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: _StatusPill(icon: icon, label: label),
      ),
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
