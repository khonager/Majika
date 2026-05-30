import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/user_taste_signals.dart';

abstract class MediaService {
  String get id;
  String get displayName;

  Future<List<MediaItem>> fetchUserLibrary(String userName);

  Future<UserTasteSignals> fetchTasteSignals(String userName);

  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  });

  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  );

  Future<List<String>> fetchAvailableTags();
}

abstract class ServiceAuthStrategy {
  String get serviceId;
  bool get supportsOAuth;

  Future<void> signIn();

  Future<void> signOut();
}

class OAuthNotConfiguredStrategy implements ServiceAuthStrategy {
  @override
  final String serviceId;

  const OAuthNotConfiguredStrategy(this.serviceId);

  @override
  bool get supportsOAuth => true;

  @override
  Future<void> signIn() {
    throw UnsupportedError(
      'OAuth for $serviceId is planned, but no client credentials are configured yet.',
    );
  }

  @override
  Future<void> signOut() async {}
}
