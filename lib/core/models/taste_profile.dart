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

  factory TasteProfile.fromJson(Map<String, dynamic> json) {
    return TasteProfile(
      userName: json['userName'] as String? ?? '',
      library: _mediaItemsFromJson(json['library']),
      favoriteGenres: _stringList(json['favoriteGenres']),
      tagWeights: _doubleMap(json['tagWeights']),
      formatWeights: _doubleMap(json['formatWeights']),
      formatCounts: _intMap(json['formatCounts']),
      favoriteCharacters: _stringList(json['favoriteCharacters']),
      favoriteStaff: _stringList(json['favoriteStaff']),
      favoriteStudios: _stringList(json['favoriteStudios']),
      highRatedItems: _mediaItemsFromJson(json['highRatedItems']),
      recentActivity: json['recentActivity'] is Map
          ? MediaItem.fromJson(
              Map<String, dynamic>.from(json['recentActivity'] as Map),
            )
          : null,
      completedCount: json['completedCount'] as int? ?? 0,
      currentCount: json['currentCount'] as int? ?? 0,
      importedAt:
          DateTime.tryParse(json['importedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      serviceId: json['serviceId'] as String? ?? 'com.majika.service.anilist',
      serviceName: json['serviceName'] as String? ?? 'AniList',
      displayName: json['displayName'] as String?,
      avatarUrl: json['avatarUrl'] as String? ?? '',
      profileUrl: json['profileUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'library': library.map((item) => item.toJson()).toList(),
      'favoriteGenres': favoriteGenres,
      'tagWeights': tagWeights,
      'formatWeights': formatWeights,
      'formatCounts': formatCounts,
      'favoriteCharacters': favoriteCharacters,
      'favoriteStaff': favoriteStaff,
      'favoriteStudios': favoriteStudios,
      'highRatedItems': highRatedItems.map((item) => item.toJson()).toList(),
      'recentActivity': recentActivity?.toJson(),
      'completedCount': completedCount,
      'currentCount': currentCount,
      'importedAt': importedAt.toIso8601String(),
      'serviceId': serviceId,
      'serviceName': serviceName,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'profileUrl': profileUrl,
    };
  }

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

  static List<MediaItem> _mediaItemsFromJson(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) MediaItem.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }

  static Map<String, double> _doubleMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).toDouble(),
    };
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).toInt(),
    };
  }
}
