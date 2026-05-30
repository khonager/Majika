import 'package:majika/core/models/media_item.dart';

class Recommendation {
  final MediaItem item;
  final double matchScore;
  final String reason;
  final List<String> signals;
  final bool isTopPick;
  final bool isAiPick;
  final bool isPopularNow;

  const Recommendation({
    required this.item,
    required this.matchScore,
    required this.reason,
    required this.signals,
    this.isTopPick = false,
    this.isAiPick = false,
    this.isPopularNow = false,
  });

  Recommendation copyWith({
    MediaItem? item,
    double? matchScore,
    String? reason,
    List<String>? signals,
    bool? isTopPick,
    bool? isAiPick,
    bool? isPopularNow,
  }) {
    return Recommendation(
      item: item ?? this.item,
      matchScore: matchScore ?? this.matchScore,
      reason: reason ?? this.reason,
      signals: signals ?? this.signals,
      isTopPick: isTopPick ?? this.isTopPick,
      isAiPick: isAiPick ?? this.isAiPick,
      isPopularNow: isPopularNow ?? this.isPopularNow,
    );
  }
}
