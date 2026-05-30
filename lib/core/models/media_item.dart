class MediaItem {
  final String id;
  final String title;
  final String coverUrl;
  final List<String> tags;
  final double? rating;
  final String subtitle;
  final String extensionId;
  final String sourceId;
  final String mediaType;
  final String format;
  final String? status;
  final String? description;
  final int? startYear;
  final int? popularity;
  final int? updatedAt;
  final bool isAdult;

  MediaItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.tags,
    this.rating,
    this.subtitle = '',
    this.extensionId = '',
    String? sourceId,
    this.mediaType = 'ANIME',
    this.format = 'UNKNOWN',
    this.status,
    this.description,
    this.startYear,
    this.popularity,
    this.updatedAt,
    this.isAdult = false,
  }) : sourceId = sourceId ?? extensionId;

  bool get hasCover => coverUrl.isNotEmpty;

  String get serviceLabel {
    if (sourceId.contains('anilist') || extensionId.contains('anilist')) {
      return 'AniList';
    }
    return sourceId.isEmpty ? 'Source' : sourceId;
  }

  MediaItem copyWith({
    String? id,
    String? title,
    String? coverUrl,
    List<String>? tags,
    double? rating,
    String? subtitle,
    String? extensionId,
    String? sourceId,
    String? mediaType,
    String? format,
    String? status,
    String? description,
    int? startYear,
    int? popularity,
    int? updatedAt,
    bool? isAdult,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      tags: tags ?? this.tags,
      rating: rating ?? this.rating,
      subtitle: subtitle ?? this.subtitle,
      extensionId: extensionId ?? this.extensionId,
      sourceId: sourceId ?? this.sourceId,
      mediaType: mediaType ?? this.mediaType,
      format: format ?? this.format,
      status: status ?? this.status,
      description: description ?? this.description,
      startYear: startYear ?? this.startYear,
      popularity: popularity ?? this.popularity,
      updatedAt: updatedAt ?? this.updatedAt,
      isAdult: isAdult ?? this.isAdult,
    );
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      title: json['title'] as String,
      coverUrl: json['coverUrl'] as String? ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      rating: json['rating'] != null
          ? (json['rating'] as num).toDouble()
          : null,
      subtitle: json['subtitle'] as String? ?? '',
      extensionId: json['extensionId'] as String? ?? '',
      sourceId: json['sourceId'] as String?,
      mediaType: json['mediaType'] as String? ?? 'ANIME',
      format: json['format'] as String? ?? 'UNKNOWN',
      status: json['status'] as String?,
      description: json['description'] as String?,
      startYear: json['startYear'] as int?,
      popularity: json['popularity'] as int?,
      updatedAt: json['updatedAt'] as int?,
      isAdult: json['isAdult'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'coverUrl': coverUrl,
      'tags': tags,
      'rating': rating,
      'subtitle': subtitle,
      'extensionId': extensionId,
      'sourceId': sourceId,
      'mediaType': mediaType,
      'format': format,
      'status': status,
      'description': description,
      'startYear': startYear,
      'popularity': popularity,
      'updatedAt': updatedAt,
      'isAdult': isAdult,
    };
  }
}
