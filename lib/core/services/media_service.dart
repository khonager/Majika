import 'package:majika/core/models/media_item.dart';

abstract class MediaService {
  String get id;
  String get displayName;

  Future<List<MediaItem>> fetchUserLibrary(String userName);

  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  });
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
