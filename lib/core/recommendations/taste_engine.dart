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
  }) {
    final genreWeights = <String, double>{};
    final formatWeights = <String, double>{};
    final formatCounts = <String, int>{};
    var completedCount = 0;
    var currentCount = 0;

    for (final item in library) {
      final status = item.status ?? '';
      if (status == 'COMPLETED') completedCount += 1;
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
      ...query.inferredTags(availableTags),
    };
    final requestedFormats = query.formats.isNotEmpty
        ? query.formats
        : query.inferredFormats();
    final requestedMediaTypes = query.mediaTypes.isNotEmpty
        ? query.mediaTypes
        : query.inferredMediaTypes();
    final includeAdult = query.includeAdult || query.infersAdult;

    for (final candidate in candidates) {
      if (libraryIds.contains(candidate.id)) continue;
      if (candidate.isAdult && !includeAdult) continue;
      if (requestedMediaTypes.isNotEmpty &&
          !requestedMediaTypes.contains(candidate.mediaType)) {
        continue;
      }
      if (requestedFormats.isNotEmpty &&
          !requestedFormats.contains(candidate.format)) {
        continue;
      }
      if (requestedTags.isNotEmpty &&
          !candidate.tags.any(requestedTags.contains)) {
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
        score += requestedGenreMatches.length * 4.0;
        signals.addAll(requestedGenreMatches.map((tag) => 'wanted $tag'));
      }

      if (requestedFormats.contains(candidate.format)) {
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

      if (query.request.trim().isNotEmpty) {
        score += _requestTextScore(candidate, query.request);
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

    final calibrated = _calibrateScores(recommendations);
    return [calibrated.first.copyWith(isTopPick: true), ...calibrated.skip(1)];
  }

  MediaItem? _recentActivity(List<MediaItem> library) {
    final current = library
        .where((item) => item.status == 'CURRENT' || item.status == 'REPEATING')
        .toList();
    final candidates = current.isNotEmpty ? current : [...library];
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
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
      return 'Includes character signals you have favorited on AniList.';
    }

    if (studioMatches.isNotEmpty) {
      return 'Comes from a studio you have favorited on AniList.';
    }

    if (candidate.rating != null && candidate.rating! >= 8) {
      return 'A strong community signal that still fits your broader AniList pattern.';
    }

    return 'Recommended from your AniList profile and current popular releases.';
  }

  List<String> _uniqueSignals(List<String> signals) {
    final seen = <String>{};
    return [
      for (final signal in signals)
        if (seen.add(signal)) signal,
    ];
  }

  double _requestTextScore(MediaItem candidate, String request) {
    final terms = request
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9+]+'))
        .where((term) => term.length > 2)
        .toList();
    if (terms.isEmpty) return 0;

    final title = candidate.title.toLowerCase();
    final description = (candidate.description ?? '').toLowerCase();
    final tags = candidate.tags.join(' ').toLowerCase();
    var score = 0.0;

    for (final term in terms) {
      if (title.contains(term)) score += 1.6;
      if (tags.contains(term)) score += 1.1;
      if (description.contains(term)) score += 0.5;
    }

    return min(score, 5.0);
  }

  double _libraryItemWeight(MediaItem item) {
    final rating = item.rating;
    final ratingWeight = rating == null ? 0.8 : max(0.15, rating / 7.2);
    final status = item.status ?? '';
    final statusWeight = switch (status) {
      'CURRENT' => 1.25,
      'REPEATING' => 1.2,
      'COMPLETED' => 1.1,
      'PAUSED' => 0.7,
      'DROPPED' => 0.35,
      'PLANNING' => 0.45,
      _ => 0.85,
    };
    final updatedAt = item.updatedAt;
    final recentWeight = updatedAt == null
        ? 1.0
        : DateTime.fromMillisecondsSinceEpoch(
            updatedAt * 1000,
          ).isAfter(DateTime.now().subtract(const Duration(days: 180)))
        ? 1.12
        : 1.0;

    return ratingWeight * statusWeight * recentWeight;
  }

  List<Recommendation> _calibrateScores(
    List<_ScoredRecommendation> recommendations,
  ) {
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
}

class _ScoredRecommendation {
  final double rawScore;
  final Recommendation recommendation;

  const _ScoredRecommendation({
    required this.rawScore,
    required this.recommendation,
  });
}
