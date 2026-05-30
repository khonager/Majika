import 'package:majika/core/models/media_item.dart';

class Recommendation {
  final MediaItem item;
  final double matchScore;
  final String reason;
  final List<String> signals;
  final bool isTopPick;
  final bool isPopularNow;

  const Recommendation({
    required this.item,
    required this.matchScore,
    required this.reason,
    required this.signals,
    this.isTopPick = false,
    this.isPopularNow = false,
  });

  Recommendation copyWith({
    MediaItem? item,
    double? matchScore,
    String? reason,
    List<String>? signals,
    bool? isTopPick,
    bool? isPopularNow,
  }) {
    return Recommendation(
      item: item ?? this.item,
      matchScore: matchScore ?? this.matchScore,
      reason: reason ?? this.reason,
      signals: signals ?? this.signals,
      isTopPick: isTopPick ?? this.isTopPick,
      isPopularNow: isPopularNow ?? this.isPopularNow,
    );
  }
}
