import 'package:majika/core/models/media_item.dart';

class TasteProfile {
  final String userName;
  final List<MediaItem> library;
  final List<String> favoriteGenres;
  final Map<String, double> tagWeights;
  final Map<String, double> formatWeights;
  final Map<String, int> formatCounts;
  final List<String> favoriteCharacters;
  final List<String> favoriteStaff;
  final List<String> favoriteStudios;
  final List<MediaItem> highRatedItems;
  final MediaItem? recentActivity;
  final int completedCount;
  final int currentCount;
  final DateTime importedAt;
  final String serviceId;
  final String serviceName;
  final String displayName;
  final String avatarUrl;
  final String profileUrl;

  const TasteProfile({
    required this.userName,
    required this.library,
    required this.favoriteGenres,
    required this.tagWeights,
    required this.formatWeights,
    required this.formatCounts,
    required this.favoriteCharacters,
    required this.favoriteStaff,
    required this.favoriteStudios,
    required this.highRatedItems,
    required this.recentActivity,
    required this.completedCount,
    required this.currentCount,
    required this.importedAt,
    this.serviceId = 'com.majika.service.anilist',
    this.serviceName = 'AniList',
    String? displayName,
    this.avatarUrl = '',
    this.profileUrl = '',
  }) : displayName = displayName ?? userName;

  bool get isEmpty => library.isEmpty;

  String get primaryTaste {
    if (favoriteGenres.isEmpty) return 'fresh recommendations';
    if (favoriteGenres.length == 1) return favoriteGenres.first;
    return '${favoriteGenres[0]} + ${favoriteGenres[1]}';
  }

  String get summary {
    if (isEmpty) {
      return 'No public list entries were found yet.';
    }

    final genres = favoriteGenres.take(3).join(', ');
    final completed = completedCount == 1
        ? '1 completed title'
        : '$completedCount completed titles';
    final current = currentCount == 1
        ? '1 current title'
        : '$currentCount current titles';

    if (serviceName == 'Steam') {
      return 'Built from ${library.length} Steam games: $completed in library, $current recently active, with strongest signals around $genres.';
    }

    return 'Built from ${library.length} $serviceName entries: $completed, $current, with strongest signals around $genres.';
  }
}
