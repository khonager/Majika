class MediaItem {
  final String id;
  final String title;
  final String coverUrl;
  final List<String> tags;
  final double? rating;
  final String subtitle;
  final String extensionId;

  MediaItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.tags,
    this.rating,
    required this.subtitle,
    required this.extensionId,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      title: json['title'] as String,
      coverUrl: json['coverUrl'] as String,
      tags: List<String>.from(json['tags'] ?? []),
      rating: json['rating'] != null ? (json['rating'] as num).toDouble() : null,
      subtitle: json['subtitle'] as String? ?? '',
      extensionId: json['extensionId'] as String,
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
    };
  }
}
