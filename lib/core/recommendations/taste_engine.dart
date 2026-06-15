import 'dart:math';

import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/models/user_taste_signals.dart';

class TasteEngine {
  TasteProfile buildProfile(
    String userName,
    List<MediaItem> library, {
    UserTasteSignals signals = UserTasteSignals.empty,
    String serviceId = 'com.majika.service.anilist',
    String serviceName = 'AniList',
    String? displayName,
    String avatarUrl = '',
    String profileUrl = '',
  }) {
    final genreWeights = <String, double>{};
    final formatWeights = <String, double>{};
    final formatCounts = <String, int>{};
    var completedCount = 0;
    var currentCount = 0;

    for (final item in library) {
      final status = item.status ?? '';
      if (status == 'OWNED') completedCount += 1;
      if (status == 'COMPLETED') completedCount += 1;
      if (status == 'RECENTLY_PLAYED') currentCount += 1;
      if (status == 'CURRENT' || status == 'REPEATING') currentCount += 1;

      formatCounts.update(item.format, (count) => count + 1, ifAbsent: () => 1);

      final itemWeight = _libraryItemWeight(item);
      formatWeights.update(
        item.format,
        (weight) => weight + itemWeight,
        ifAbsent: () => itemWeight,
      );

      for (final genre in item.tags) {
        genreWeights.update(
          genre,
          (weight) => weight + itemWeight,
          ifAbsent: () => itemWeight,
        );
      }
    }

    final favoriteGenres = genreWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final highRatedItems = [...library]
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

    final recentActivity = _recentActivity(library);

    return TasteProfile(
      userName: userName,
      library: library,
      favoriteGenres: favoriteGenres.map((entry) => entry.key).take(8).toList(),
      tagWeights: genreWeights,
      formatWeights: formatWeights,
      formatCounts: formatCounts,
      favoriteCharacters: signals.favoriteCharacters,
      favoriteStaff: signals.favoriteStaff,
      favoriteStudios: signals.favoriteStudios,
      highRatedItems: highRatedItems.take(6).toList(),
      recentActivity: recentActivity,
      completedCount: completedCount,
      currentCount: currentCount,
      importedAt: DateTime.now(),
      serviceId: serviceId,
      serviceName: serviceName,
      displayName: displayName,
      avatarUrl: avatarUrl,
      profileUrl: profileUrl,
    );
  }

  List<Recommendation> rankCandidates(
    TasteProfile profile,
    List<MediaItem> candidates, {
    RecommendationQuery query = const RecommendationQuery(),
  }) {
    final libraryIds = profile.library.map((item) => item.id).toSet();
    final recommendations = <_ScoredRecommendation>[];
    final availableTags = {
      ...profile.favoriteGenres,
      for (final candidate in candidates) ...candidate.tags,
    };
    final requestedTags = {
      ...query.selectedTags,
      ...query.aiSelectedTags,
      ...query.inferredTags(availableTags),
    };
    final specificRequestedTags = query.specificRequestedTags(availableTags);
    final hardRequestedTags = {...query.selectedTags, ...specificRequestedTags};
    final requestedFormats = query.effectiveFormats();
    final requestedMediaTypes = query.effectiveMediaTypes();
    final requireLocalCoOp = query.infersLocalCoOp;
    final includeAdult = query.allowsAdult;

    for (final candidate in candidates) {
      if (libraryIds.contains(candidate.id)) continue;
      if (candidate.isAdult && !includeAdult) continue;
      if (requestedMediaTypes.isNotEmpty &&
          !requestedMediaTypes.contains(candidate.mediaType)) {
        continue;
      }
      if (requestedFormats.isNotEmpty &&
          !_matchesRequestedFormats(
            candidate,
            requestedFormats,
            requireLocalCoOp: requireLocalCoOp,
          )) {
        continue;
      }
      if (hardRequestedTags.isNotEmpty &&
          !_matchesSpecificRequestedTags(candidate, hardRequestedTags)) {
        continue;
      }
      if (!query.matchesText(candidate)) continue;

      final signals = <String>[];
      var score = 0.0;

      final genreMatches = candidate.tags
          .where(profile.favoriteGenres.contains)
          .take(4)
          .toList();
      if (genreMatches.isNotEmpty) {
        score += genreMatches.fold<double>(
          0,
          (total, tag) => total + min(profile.tagWeights[tag] ?? 0, 10) * 0.7,
        );
        signals.addAll(genreMatches);
      }

      final formatAffinity = profile.formatWeights[candidate.format] ?? 0;
      if (formatAffinity > 0) {
        score += min(formatAffinity, 8) * 0.4;
        signals.add(candidate.format.replaceAll('_', ' '));
      }

      if (candidate.rating != null) {
        score += max(0, candidate.rating! - 6) * 0.85;
      }

      if (profile.serviceName == 'Steam') {
        score += _steamCandidateScore(candidate);
      }

      final characterMatches = candidate.characters
          .where(profile.favoriteCharacters.contains)
          .take(3)
          .toList();
      if (characterMatches.isNotEmpty) {
        score += characterMatches.length * 3.4;
        signals.addAll(characterMatches.map((name) => 'favorite $name'));
      }

      final studioMatches = candidate.studios
          .where(profile.favoriteStudios.contains)
          .take(2)
          .toList();
      if (studioMatches.isNotEmpty) {
        score += studioMatches.length * 2.6;
        signals.addAll(studioMatches.map((name) => 'favorite studio $name'));
      }

      final popularity = candidate.popularity ?? 0;
      if (popularity > 0) {
        score += min(log(popularity + 1) / log(10), 5) * 0.35;
      }
      if (popularity > 20000) {
        signals.add('popular now');
      }

      if ((candidate.startYear ?? 0) >= DateTime.now().year - 1) {
        score += 0.9;
        signals.add('recent release');
      }

      final requestedGenreMatches = candidate.tags
          .where(requestedTags.contains)
          .take(4)
          .toList();
      if (requestedGenreMatches.isNotEmpty) {
        score += requestedGenreMatches.length * 6.0;
        signals.addAll(requestedGenreMatches.map((tag) => 'wanted $tag'));
      }

      if (_matchesRequestedFormats(
        candidate,
        requestedFormats,
        requireLocalCoOp: requireLocalCoOp,
      )) {
        score += 3.2;
        signals.add('wanted ${candidate.format.replaceAll('_', ' ')}');
      }

      if (requestedMediaTypes.contains(candidate.mediaType)) {
        score += 2.2;
        signals.add('wanted ${candidate.mediaType.toLowerCase()}');
      }

      if (candidate.isAdult && includeAdult) {
        score += 0.8;
        signals.add('adult filter');
      }

      final hasNaturalLanguageRequest = query.request.trim().isNotEmpty;
      if (hasNaturalLanguageRequest) {
        final requestTextScore = _requestTextScore(candidate, query.request);
        final codingHackScore = _codingHackIntentScore(
          candidate,
          query.request,
        );
        final vrClimbingIntentScore = _vrClimbingIntentScore(
          candidate,
          query.request,
        );
        final unusualInputControlScore = _unusualInputControlIntentScore(
          candidate,
          query.request,
        );
        final superpoweredOpenWorldScore = _superpoweredOpenWorldIntentScore(
          candidate,
          query.request,
        );
        final mundanePowerScore = _mundanePowerIntentScore(
          candidate,
          query.request,
        );
        final requestTagEvidenceScore = _requestTagEvidenceScore(
          candidate,
          requestedTags,
        );
        final hasAdultRequestEvidence =
            _isAdultRequest(query, requestedTags) &&
            _hasAdultEvidence(candidate);
        score += requestTextScore * 2.4;
        score += codingHackScore * 3.4;
        score += vrClimbingIntentScore * 4.0;
        score += unusualInputControlScore * 3.6;
        score += superpoweredOpenWorldScore * 4.0;
        score += mundanePowerScore * 4.0;
        score += requestTagEvidenceScore * 2.0;
        final hasRequestEvidence =
            requestTextScore > 0 ||
            codingHackScore > 0 ||
            vrClimbingIntentScore > 0 ||
            unusualInputControlScore > 0 ||
            superpoweredOpenWorldScore > 0 ||
            mundanePowerScore > 0 ||
            requestTagEvidenceScore > 0 ||
            requestedGenreMatches.isNotEmpty ||
            hasAdultRequestEvidence;
        if (_isCodingHackRequest(query.request) && codingHackScore <= 0) {
          continue;
        }
        if (_isSuperpoweredOpenWorldRequest(query.request) &&
            superpoweredOpenWorldScore <= 0) {
          continue;
        }
        if (_isMundanePowerRequest(query.request) && mundanePowerScore <= 0) {
          continue;
        }
        if (_requiresRequestEvidence(query, requestedTags) &&
            !hasRequestEvidence) {
          continue;
        }
        if (vrClimbingIntentScore > 0) {
          signals.add('wanted VR climbing');
        }
        if (unusualInputControlScore > 0) {
          signals.add('wanted unusual controls');
        }
        if (superpoweredOpenWorldScore > 0) {
          signals.add('wanted superpowered open world');
        }
        if (mundanePowerScore > 0) {
          signals.add('wanted mundane job hidden power');
        }
      }

      if (score <= 0) continue;

      recommendations.add(
        _ScoredRecommendation(
          rawScore: score,
          recommendation: Recommendation(
            item: candidate,
            matchScore: score,
            reason: _reasonFor(
              candidate,
              genreMatches,
              characterMatches,
              studioMatches,
              profile,
              query,
            ),
            signals: _uniqueSignals(signals),
            isPopularNow: (candidate.popularity ?? 0) > 20000,
          ),
        ),
      );
    }

    recommendations.sort((a, b) => b.rawScore.compareTo(a.rawScore));
    if (recommendations.isEmpty) return [];

    final calibrated = _calibrateScores(recommendations, query: query);
    return [calibrated.first.copyWith(isTopPick: true), ...calibrated.skip(1)];
  }

  MediaItem? _recentActivity(List<MediaItem> library) {
    final current = library
        .where(
          (item) =>
              item.status == 'CURRENT' ||
              item.status == 'REPEATING' ||
              item.status == 'RECENTLY_PLAYED',
        )
        .toList();
    final candidates = current.isNotEmpty ? current : [...library];
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final bTime = b.lastPlayedAt ?? b.updatedAt ?? 0;
      final aTime = a.lastPlayedAt ?? a.updatedAt ?? 0;
      return bTime.compareTo(aTime);
    });
    return candidates.first;
  }

  String _reasonFor(
    MediaItem candidate,
    List<String> genreMatches,
    List<String> characterMatches,
    List<String> studioMatches,
    TasteProfile profile,
    RecommendationQuery query,
  ) {
    if (query.isActive) {
      final request = query.request.trim();
      final queryLead = request.isEmpty ? 'your filters' : '"$request"';
      final strongestSignal = candidate.tags.isNotEmpty
          ? candidate.tags.take(2).join(' and ')
          : candidate.format.replaceAll('_', ' ');
      return 'Found for $queryLead: $strongestSignal fits the request while staying close to ${profile.primaryTaste}.';
    }

    if (genreMatches.isNotEmpty) {
      final genres = genreMatches.take(2).join(' and ');
      return 'Matches your $genres streak and keeps close to the ${profile.primaryTaste} profile.';
    }

    if (characterMatches.isNotEmpty) {
      return 'Includes character signals you have favorited on ${profile.serviceName}.';
    }

    if (studioMatches.isNotEmpty) {
      return 'Comes from a creator signal you have favorited on ${profile.serviceName}.';
    }

    if (candidate.rating != null && candidate.rating! >= 8) {
      return 'A strong community signal that still fits your broader AniList pattern.';
    }

    return 'Recommended from your ${profile.serviceName} profile and current popular releases.';
  }

  bool _matchesSpecificRequestedTags(
    MediaItem candidate,
    Set<String> specificRequestedTags,
  ) {
    if (candidate.tags.any(specificRequestedTags.contains)) return true;
    final haystack = _normalizedEvidenceText(candidate);
    for (final tag in specificRequestedTags) {
      final hints = _requestTagEvidenceHints[tag];
      if (hints != null &&
          hints.any((hint) => _containsWholePhrase(haystack, hint))) {
        return true;
      }
    }
    if (candidate.isAdult &&
        specificRequestedTags.any(_adultRequestTags.contains)) {
      return true;
    }
    return false;
  }

  List<String> _uniqueSignals(List<String> signals) {
    final seen = <String>{};
    return [
      for (final signal in signals)
        if (seen.add(signal)) signal,
    ];
  }

  double _requestTextScore(MediaItem candidate, String request) {
    final terms = _requestTextTerms(request);
    if (terms.isEmpty) return 0;

    final title = candidate.title.toLowerCase();
    final description = (candidate.description ?? '').toLowerCase();
    final tags = candidate.tags.join(' ').toLowerCase();
    final titleTokens = _textTokens(candidate.title);
    final descriptionTokens = _textTokens(candidate.description ?? '');
    final tagTokens = _textTokens(candidate.tags.join(' '));
    var score = 0.0;

    for (final term in terms) {
      if (_matchesRequestTerm(title, titleTokens, term)) score += 1.6;
      if (_matchesRequestTerm(tags, tagTokens, term)) score += 1.1;
      if (_matchesRequestTerm(description, descriptionTokens, term)) {
        score += 0.5;
      }
    }

    return min(score, 5.0);
  }

  List<String> _requestTextTerms(String request) {
    final codingHackIntent = _isCodingHackRequest(request);
    return request
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9+]+'))
        .where(
          (term) =>
              term.length > 2 &&
              !_requestTextStopWords.contains(term) &&
              !_requestStructuralTerms.contains(term) &&
              !(codingHackIntent && _codingHackLowSignalTerms.contains(term)) &&
              !_lowSignalRequestTerms.contains(term),
        )
        .toList();
  }

  double _codingHackIntentScore(MediaItem candidate, String request) {
    if (!_isCodingHackRequest(request)) return 0;
    final haystack = _normalizedEvidenceText(candidate);
    var score = 0.0;
    for (final group in _codingHackEvidenceGroups) {
      if (group.any((hint) => _containsWholePhrase(haystack, hint))) {
        score += 1.0;
      }
    }

    final normalizedTitle = candidate.title.toLowerCase();
    for (final titleHint in _codingHackTitleHints) {
      if (_containsWholePhrase(normalizedTitle, titleHint)) {
        score += 1.4;
      }
    }

    return min(score, 4.5);
  }

  double _vrClimbingIntentScore(MediaItem candidate, String request) {
    if (!_isVrClimbingRequest(request)) return 0;
    if (!_hasVrEvidence(candidate)) return 0;

    final haystack = _normalizedEvidenceText(candidate);
    var score = 0.0;

    if (_vrClimbingEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    )) {
      score += 1.2;
    }
    if (_containsWholePhrase(haystack, 'vr') &&
        _containsWholePhrase(haystack, 'climb')) {
      score += 0.6;
    }

    return min(score, 4.2);
  }

  double _unusualInputControlIntentScore(MediaItem candidate, String request) {
    final faceRequest = _isFaceControlRequest(request);
    final voiceRequest = _isVoiceControlRequest(request);
    if (!faceRequest && !voiceRequest) return 0;

    final haystack = _normalizedEvidenceText(candidate);
    var score = 0.0;

    if (faceRequest &&
        _faceControlEvidenceTerms.any(
          (term) => _containsWholePhrase(haystack, term),
        )) {
      score += 1.5;
    }
    if (voiceRequest &&
        _voiceControlEvidenceTerms.any(
          (term) => _containsWholePhrase(haystack, term),
        )) {
      score += 1.4;
    }

    return min(score, 4.2);
  }

  double _superpoweredOpenWorldIntentScore(
    MediaItem candidate,
    String request,
  ) {
    if (!_isSuperpoweredOpenWorldRequest(request)) return 0;

    final haystack = _normalizedEvidenceText(candidate);
    var score = 0.0;

    if (_superpoweredOpenWorldEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    )) {
      score += 1.4;
    }
    if (_superpoweredTraversalEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    )) {
      score += 1.1;
    }
    if (_containsWholePhrase(haystack, 'open world') &&
        _superpoweredOpenWorldEvidenceTerms.any(
          (term) => _containsWholePhrase(haystack, term),
        )) {
      score += 0.8;
    }

    return min(score, 4.5);
  }

  double _mundanePowerIntentScore(MediaItem candidate, String request) {
    if (!_isMundanePowerRequest(request)) return 0;

    final haystack = _normalizedEvidenceText(candidate);
    final hasMundaneWorkEvidence = _mundaneWorkEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    );
    final hasPowerEvidence = _mundanePowerEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    );
    if (!hasMundaneWorkEvidence || !hasPowerEvidence) return 0;

    var score = 2.6;
    if (_hiddenPowerEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    )) {
      score += 1.0;
    }
    if (_comedicMundanePowerEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    )) {
      score += 0.6;
    }

    return min(score, 4.2);
  }

  double _requestTagEvidenceScore(
    MediaItem candidate,
    Set<String> requestedTags,
  ) {
    if (requestedTags.isEmpty) return 0;
    final haystack = _normalizedEvidenceText(candidate);
    var score = 0.0;
    for (final tag in requestedTags) {
      final hints = _requestTagEvidenceHints[tag];
      if (hints == null) continue;
      if (hints.any((hint) => _containsWholePhrase(haystack, hint))) {
        score += 1.0;
      }
    }
    return min(score, 3.0);
  }

  bool _requiresRequestEvidence(
    RecommendationQuery query,
    Set<String> requestedTags,
  ) {
    return requestedTags.isNotEmpty ||
        _isAdultRequest(query, requestedTags) ||
        _isCodingHackRequest(query.request) ||
        _isUnusualInputControlRequest(query.request);
  }

  bool _isAdultRequest(RecommendationQuery query, Set<String> requestedTags) {
    return query.infersAdult || requestedTags.any(_adultRequestTags.contains);
  }

  bool _hasAdultEvidence(MediaItem candidate) {
    if (candidate.isAdult) return true;
    final haystack = _normalizedEvidenceText(candidate);
    return _adultEvidenceTerms.any(
      (term) => _containsWholePhrase(haystack, term),
    );
  }

  bool _isCodingHackRequest(String request) {
    final normalized = request.toLowerCase();
    return _codingHackRequestTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
  }

  bool _isVrClimbingRequest(String request) {
    final normalized = request.toLowerCase();
    final mentionsVr =
        _containsWholePhrase(normalized, 'vr') ||
        _containsWholePhrase(normalized, 'virtual reality');
    final mentionsClimbing = _vrClimbingRequestTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
    return mentionsVr && mentionsClimbing;
  }

  bool _isFaceControlRequest(String request) {
    final normalized = request.toLowerCase();
    return _faceControlRequestTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
  }

  bool _isVoiceControlRequest(String request) {
    final normalized = request.toLowerCase();
    return _voiceControlRequestTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
  }

  bool _isUnusualInputControlRequest(String request) {
    return _isFaceControlRequest(request) || _isVoiceControlRequest(request);
  }

  bool _isSuperpoweredOpenWorldRequest(String request) {
    final normalized = request.toLowerCase();
    final mentionsReference = _superpoweredReferenceTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
    final mentionsPowers = _superpoweredRequestTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
    final mentionsOpenWorld =
        _containsWholePhrase(normalized, 'open world') ||
        _containsWholePhrase(normalized, 'sandbox');
    return mentionsReference || (mentionsPowers && mentionsOpenWorld);
  }

  bool _isMundanePowerRequest(String request) {
    final normalized = request.toLowerCase();
    final mentionsWork = _mundaneWorkRequestTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
    final mentionsPower = _mundanePowerRequestTerms.any(
      (term) => _containsWholePhrase(normalized, term),
    );
    return mentionsWork && mentionsPower;
  }

  bool _hasVrEvidence(MediaItem candidate) {
    if (candidate.tags.contains('VR')) return true;
    final haystack = _normalizedEvidenceText(candidate);
    return _requestTagEvidenceHints['VR']!.any(
      (hint) => _containsWholePhrase(haystack, hint),
    );
  }

  String _normalizedEvidenceText(MediaItem candidate) {
    return [
      candidate.title,
      candidate.subtitle,
      candidate.format,
      candidate.mediaType,
      candidate.description ?? '',
      ...candidate.tags,
    ].join(' ').toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  bool _containsWholePhrase(String text, String phrase) {
    final escaped = RegExp.escape(phrase.toLowerCase());
    return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(text);
  }

  bool _matchesRequestTerm(String text, Set<String> tokens, String term) {
    if (term.length <= 3) return tokens.contains(term);
    return tokens.contains(term) || text.contains(term);
  }

  Set<String> _textTokens(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9+]+'))
        .where((token) => token.isNotEmpty)
        .toSet();
  }

  double _libraryItemWeight(MediaItem item) {
    final rating = item.rating;
    final playtimeHours = (item.playtimeMinutes ?? 0) / 60;
    final playtimeWeight = playtimeHours <= 0
        ? 0.0
        : min(log(playtimeHours + 1) / log(10), 2.2);
    final recentPlaytimeWeight = (item.recentPlaytimeMinutes ?? 0) > 0
        ? 0.45
        : 0.0;
    final ratingWeight = rating == null
        ? 0.8 + playtimeWeight + recentPlaytimeWeight
        : max(0.15, rating / 7.2) + playtimeWeight + recentPlaytimeWeight;
    final status = item.status ?? '';
    final statusWeight = switch (status) {
      'CURRENT' => 1.25,
      'REPEATING' => 1.2,
      'COMPLETED' => 1.1,
      'PAUSED' => 0.7,
      'DROPPED' => 0.35,
      'PLANNING' => 0.45,
      'OWNED' => 0.95,
      'RECENTLY_PLAYED' => 1.28,
      _ => 0.85,
    };
    final updatedAt = item.lastPlayedAt ?? item.updatedAt;
    final recentWeight = updatedAt == null
        ? 1.0
        : DateTime.fromMillisecondsSinceEpoch(
            updatedAt * 1000,
          ).isAfter(DateTime.now().subtract(const Duration(days: 180)))
        ? 1.12
        : 1.0;

    return ratingWeight * statusWeight * recentWeight;
  }

  bool _matchesRequestedFormats(
    MediaItem item,
    Set<String> requestedFormats, {
    required bool requireLocalCoOp,
  }) {
    if (requestedFormats.isEmpty) return true;

    final steamFormats = requestedFormats
        .where(RecommendationQuery.steamFormats.contains)
        .toSet();
    final otherFormats = requestedFormats.difference(steamFormats);

    if (steamFormats.isNotEmpty &&
        !steamFormats.every(
          (format) =>
              _matchesFormat(item, format, requireLocalCoOp: requireLocalCoOp),
        )) {
      return false;
    }

    if (otherFormats.isNotEmpty &&
        !otherFormats.any(
          (format) =>
              _matchesFormat(item, format, requireLocalCoOp: requireLocalCoOp),
        )) {
      return false;
    }

    return true;
  }

  bool _matchesFormat(
    MediaItem item,
    String requestedFormat, {
    required bool requireLocalCoOp,
  }) {
    if (requestedFormat == item.format) return true;
    if (RecommendationQuery.aniListFormats.contains(requestedFormat)) {
      return RecommendationQuery.aniListReleaseFormatsFor({
        requestedFormat,
      }).contains(item.format);
    }
    final normalizedTags = item.tags
        .map((tag) => tag.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ''))
        .toSet();
    if (requestedFormat == 'CO_OP' && requireLocalCoOp) {
      return _localCoOpAliases.any(normalizedTags.contains);
    }
    return _formatAliases(requestedFormat).any(normalizedTags.contains);
  }

  Set<String> get _localCoOpAliases => const {
    'localcoop',
    'localmultiplayer',
    'sharedsplitscreencoop',
    'sharedsplitscreen',
    'splitscreencoop',
    'splitscreen',
    'remoteplaytogether',
    'lancoop',
  };

  Set<String> _formatAliases(String format) {
    return switch (format) {
      'SINGLE_PLAYER' => {'singleplayer'},
      'MULTIPLAYER' => {
        'multiplayer',
        'coop',
        'localcoop',
        'onlinecoop',
        'pvp',
        'onlinepvp',
        'remoteplaytogether',
        'sharedsplitscreencoop',
        'sharedsplitscreenpvp',
      },
      'CO_OP' => {
        'coop',
        'localcoop',
        'sharedsplitscreencoop',
        'remoteplaytogether',
      },
      'ONLINE_CO_OP' => {'onlinecoop'},
      'CONTROLLER' => {
        'controller',
        'controllersupport',
        'fullcontrollersupport',
        'partialcontrollersupport',
      },
      'STEAM_DECK' => {'steamdeck', 'steamdeckverified'},
      _ => {format.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '')},
    };
  }

  double _steamCandidateScore(MediaItem candidate) {
    var score = 0.0;
    if ((candidate.popularity ?? 0) > 0) {
      score += min(log(candidate.popularity! + 1) / log(10), 5) * 0.4;
    }
    if (candidate.tags.contains('Steam Deck')) score += 0.35;
    if (candidate.tags.contains('Controller Support')) score += 0.25;
    return score;
  }

  List<Recommendation> _calibrateScores(
    List<_ScoredRecommendation> recommendations, {
    required RecommendationQuery query,
  }) {
    if (query.isActive && recommendations.length <= 3) {
      return [
        for (final entry in recommendations)
          entry.recommendation.copyWith(
            matchScore: max(52, min(92, 50 + entry.rawScore * 2.2)),
          ),
      ];
    }

    final minScore = recommendations.last.rawScore;
    final maxScore = recommendations.first.rawScore;
    final range = maxScore - minScore;

    return [
      for (final entry in recommendations)
        entry.recommendation.copyWith(
          matchScore: range <= 0
              ? max(54, min(91, 58 + entry.rawScore * 2.4))
              : 52 + ((entry.rawScore - minScore) / range) * 47,
        ),
    ];
  }

  static const Set<String> _adultRequestTags = {
    'Hentai',
    'Ecchi',
    'Sexual Content',
    'Nudity',
    'Mature',
    'NSFW',
  };

  static const Set<String> _requestTextStopWords = {
    'about',
    'and',
    'best',
    'find',
    'for',
    'give',
    'good',
    'like',
    'lot',
    'make',
    'makes',
    'really',
    'recommend',
    'recommendation',
    'recommendations',
    'similar',
    'something',
    'that',
    'the',
    'to',
    'want',
    'with',
    'you',
  };

  static const Set<String> _requestStructuralTerms = {
    'anime',
    'book',
    'comic',
    'film',
    'films',
    'game',
    'games',
    'manga',
    'movie',
    'movies',
    'novel',
    'play',
    'steam',
    'series',
    'show',
    'shows',
    'special',
  };

  static const Set<String> _lowSignalRequestTerms = {
    'entertaining',
    'fun',
    'learn',
  };

  static const Set<String> _codingHackLowSignalTerms = {
    'hack',
    'hacking',
    'learn',
  };

  static const Set<String> _codingHackRequestTerms = {
    'code',
    'coder',
    'coding',
    'cyber',
    'cybersecurity',
    'hack',
    'hacker',
    'hackers',
    'hacking',
    'learn to code',
    'program',
    'programmer',
    'programming',
  };

  static const List<Set<String>> _codingHackEvidenceGroups = [
    {
      'code',
      'coding',
      'program',
      'programming',
      'programmer',
      'developer',
      'software',
    },
    {
      'hacknet',
      'hacker',
      'hacking',
      'cybersecurity',
      'network security',
      'terminal',
      'command line',
      'shell',
      'linux',
    },
    {
      'machine learning',
      'neural network',
      'automation',
      'logic',
      'circuit',
      'engineering',
      'assembly',
      'algorithm',
    },
  ];

  static const Set<String> _codingHackTitleHints = {
    'hacknet',
    'grey hack',
    'uplink',
    'while true',
    'shenzhen',
    'tis-100',
    'human resource machine',
    '7 billion humans',
    'exapunks',
    'quadrilateral cowboy',
    'turing complete',
    'opus magnum',
  };

  static const Set<String> _vrClimbingRequestTerms = {
    'ascend',
    'ascent',
    'climb',
    'climber',
    'climbing',
    'grapple',
    'grappling',
    'mountain',
    'mountains',
  };

  static const Set<String> _vrClimbingEvidenceTerms = {
    'ascend',
    'ascending',
    'ascent',
    'climb',
    'climbing',
    'grapple',
    'grappling',
    'grappling hook',
    'mount everest',
    'parkour',
    'vertical',
  };

  static const Set<String> _faceControlRequestTerms = {
    'blink',
    'blinks',
    'blinking',
    'camera',
    'eye',
    'eyes',
    'face',
    'facial',
    'gaze',
    'webcam',
  };

  static const Set<String> _faceControlEvidenceTerms = {
    'blink',
    'blinks',
    'blinking',
    'camera',
    'eye',
    'eyes',
    'face',
    'facial',
    'gaze',
    'webcam',
  };

  static const Set<String> _voiceControlRequestTerms = {
    'mic',
    'microphone',
    'sing',
    'singing',
    'speech',
    'voice',
  };

  static const Set<String> _voiceControlEvidenceTerms = {
    'mic',
    'microphone',
    'sing',
    'singing',
    'speech',
    'voice',
    'voice control',
    'voice controlled',
    'voice commands',
  };

  static const Set<String> _superpoweredReferenceTerms = {
    'infamous',
    'infamous second son',
    'prototype',
    'spider man',
    'spiderman',
    'sunset overdrive',
  };

  static const Set<String> _superpoweredRequestTerms = {
    'abilities',
    'ability',
    'power',
    'powers',
    'superhero',
    'superheroes',
    'superhuman',
    'superpower',
    'superpowers',
    'supernatural',
  };

  static const Set<String> _superpoweredOpenWorldEvidenceTerms = {
    'abilities',
    'ability',
    'mutant',
    'power',
    'powers',
    'super hero',
    'superhero',
    'superheroes',
    'superhuman',
    'supernatural',
    'web slinging',
    'web-slinging',
  };

  static const Set<String> _superpoweredTraversalEvidenceTerms = {
    'air dash',
    'dash',
    'free running',
    'grind',
    'grinding',
    'parkour',
    'swing',
    'swinging',
    'traversal',
    'wall run',
    'wall-run',
    'web slinging',
    'web-slinging',
    'wingsuit',
  };

  static const Set<String> _mundaneWorkRequestTerms = {
    '9 5',
    '9-5',
    'company',
    'employee',
    'job',
    'office',
    'part time',
    'part-time',
    'salaryman',
    'work',
    'worker',
    'workplace',
  };

  static const Set<String> _mundanePowerRequestTerms = {
    'actually powerful',
    'hidden power',
    'op',
    'overpowered',
    'powerful',
    'powerfull',
    'secretly powerful',
    'super powerful',
    'superpower',
    'superpowers',
  };

  static const Set<String> _mundaneWorkEvidenceTerms = {
    '9 5',
    '9-5',
    'business',
    'company',
    'convenience store',
    'corporate',
    'coworker',
    'employee',
    'fast food',
    'job',
    'office',
    'part time',
    'part-time',
    'restaurant',
    'salaryman',
    'work',
    'worker',
    'workplace',
  };

  static const Set<String> _mundanePowerEvidenceTerms = {
    'demon',
    'demon lord',
    'hidden power',
    'magic',
    'op',
    'overpowered',
    'powerful',
    'secret identity',
    'secretly powerful',
    'strongest',
    'super power',
    'superpower',
    'supernatural',
  };

  static const Set<String> _hiddenPowerEvidenceTerms = {
    'double life',
    'hidden identity',
    'hidden power',
    'ordinary life',
    'secret identity',
    'secretly',
    'undercover',
  };

  static const Set<String> _comedicMundanePowerEvidenceTerms = {
    'comedy',
    'comedic',
    'deadpan',
    'parody',
    'slice of life',
    'workplace comedy',
  };

  static const Map<String, Set<String>> _requestTagEvidenceHints = {
    'Hentai': {
      '18+',
      '18 plus',
      'adult',
      'adult visual novel',
      'eroge',
      'erotic',
      'explicit',
      'hentai',
      'horny',
      'lewd',
      'naughty',
      'nsfw',
      'porn',
      'pornography',
      'r18',
      'sex',
      'sexual',
      'sexual content',
      'sexy',
      'smut',
      'steamy',
      'uncensored',
    },
    'Ecchi': {'ecchi', 'fan service', 'fanservice', 'lewd', 'naughty', 'sexy'},
    'Sexual Content': {
      '18+',
      '18 plus',
      'adult',
      'adult visual novel',
      'erotic',
      'explicit',
      'horny',
      'lewd',
      'naughty',
      'nsfw',
      'porn',
      'sex',
      'sexual',
      'sexual content',
      'sexy',
      'smut',
      'steamy',
      'uncensored',
    },
    'Nudity': {'naked', 'naughty', 'nude', 'nudity', 'sexy', 'uncensored'},
    'Mature': {
      '18+',
      '18 plus',
      'adult',
      'adult visual novel',
      'erotic',
      'explicit',
      'mature',
      'nsfw',
      'sex',
      'sexual',
      'sexual content',
      'steamy',
    },
    'NSFW': {
      '18+',
      '18 plus',
      'adult',
      'erotic',
      'explicit',
      'horny',
      'lewd',
      'naughty',
      'nsfw',
      'porn',
      'sex',
      'sexual',
      'sexual content',
      'sexy',
      'smut',
    },
    'Comedy': {
      'absurd',
      'comedy',
      'comedic',
      'funny',
      'goofy',
      'hilarious',
      'humor',
      'humour',
      'joke',
      'jokes',
      'laugh',
      'laughing',
      'parody',
      'satire',
      'silly',
      'slapstick',
      'witty',
    },
    'Funny': {
      'absurd',
      'comedy',
      'comedic',
      'funny',
      'goofy',
      'hilarious',
      'humor',
      'humour',
      'joke',
      'jokes',
      'laugh',
      'laughing',
      'parody',
      'satire',
      'silly',
      'slapstick',
      'witty',
    },
    'VR': {
      'vr',
      'vr only',
      'vr supported',
      'tracked controller support',
      'virtual reality',
      'tracked motion controllers',
      'steamvr',
    },
  };

  static const Set<String> _adultEvidenceTerms = {
    '18+',
    '18 plus',
    'adult',
    'adult visual novel',
    'eroge',
    'erotic',
    'explicit',
    'hentai',
    'horny',
    'lewd',
    'naked',
    'naughty',
    'nude',
    'nudity',
    'nsfw',
    'porn',
    'pornography',
    'r18',
    'sex',
    'sexual',
    'sexual content',
    'sexy',
    'smut',
    'steamy',
    'uncensored',
  };
}

class _ScoredRecommendation {
  final double rawScore;
  final Recommendation recommendation;

  const _ScoredRecommendation({
    required this.rawScore,
    required this.recommendation,
  });
}
