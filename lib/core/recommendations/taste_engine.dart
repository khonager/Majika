import 'dart:math';

import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/taste_profile.dart';

class TasteEngine {
  TasteProfile buildProfile(String userName, List<MediaItem> library) {
    final genreWeights = <String, double>{};
    final formatCounts = <String, int>{};
    var completedCount = 0;
    var currentCount = 0;

    for (final item in library) {
      final status = item.status ?? '';
      if (status == 'COMPLETED') completedCount += 1;
      if (status == 'CURRENT' || status == 'REPEATING') currentCount += 1;

      formatCounts.update(item.format, (count) => count + 1, ifAbsent: () => 1);

      final ratingBoost = item.rating == null ? 0.75 : max(0.4, item.rating!);
      final statusBoost = status == 'COMPLETED' || status == 'CURRENT'
          ? 1.15
          : 1.0;
      for (final genre in item.tags) {
        genreWeights.update(
          genre,
          (weight) => weight + ratingBoost * statusBoost,
          ifAbsent: () => ratingBoost * statusBoost,
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
      formatCounts: formatCounts,
      highRatedItems: highRatedItems.take(6).toList(),
      recentActivity: recentActivity,
      completedCount: completedCount,
      currentCount: currentCount,
      importedAt: DateTime.now(),
    );
  }

  List<Recommendation> rankCandidates(
    TasteProfile profile,
    List<MediaItem> candidates,
  ) {
    final libraryIds = profile.library.map((item) => item.id).toSet();
    final recommendations = <Recommendation>[];

    for (final candidate in candidates) {
      if (libraryIds.contains(candidate.id)) continue;

      final signals = <String>[];
      var score = 0.0;

      final genreMatches = candidate.tags
          .where(profile.favoriteGenres.contains)
          .take(4)
          .toList();
      if (genreMatches.isNotEmpty) {
        score += genreMatches.length * 2.8;
        signals.addAll(genreMatches);
      }

      final formatAffinity = profile.formatCounts[candidate.format] ?? 0;
      if (formatAffinity > 0) {
        score += min(formatAffinity, 6) * 0.45;
        signals.add(candidate.format.replaceAll('_', ' '));
      }

      if (candidate.rating != null) {
        score += candidate.rating! * 0.85;
      }

      if ((candidate.popularity ?? 0) > 20000) {
        score += 0.8;
        signals.add('popular now');
      }

      if ((candidate.startYear ?? 0) >= DateTime.now().year - 1) {
        score += 0.7;
        signals.add('recent release');
      }

      if (score <= 0) continue;

      recommendations.add(
        Recommendation(
          item: candidate,
          matchScore: score,
          reason: _reasonFor(candidate, genreMatches, profile),
          signals: _uniqueSignals(signals),
          isPopularNow: (candidate.popularity ?? 0) > 20000,
        ),
      );
    }

    recommendations.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    if (recommendations.isEmpty) return [];

    return [
      recommendations.first.copyWith(isTopPick: true),
      ...recommendations.skip(1),
    ];
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
    TasteProfile profile,
  ) {
    if (genreMatches.isNotEmpty) {
      final genres = genreMatches.take(2).join(' and ');
      return 'Matches your $genres streak and keeps close to the ${profile.primaryTaste} profile.';
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
}
