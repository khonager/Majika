import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/services/anilist_service.dart';
import 'package:majika/core/services/steam_service.dart';

// Explicitly opt in: normal test runs must not depend on public API availability.
const _runLive = bool.fromEnvironment('RUN_LIVE_CATALOG');

void main() {
  test('live AniList catalog normalizes public recommendations', () async {
    final client = http.Client();
    addTearDown(client.close);
    final candidates = await AniListService(client: client).fetchRecommendationCandidates();
    expect(candidates, isNotEmpty);
    expect(candidates.every((item) => item.id.isNotEmpty && item.title.isNotEmpty), isTrue);
    expect(candidates.every((item) => !item.isAdult), isTrue);
  }, skip: !_runLive, timeout: const Timeout(Duration(minutes: 2)));

  test('live Steam catalog normalizes public recommendations', () async {
    final client = http.Client();
    addTearDown(client.close);
    final candidates = await SteamService(client: client).fetchRecommendationCandidates();
    expect(candidates, isNotEmpty);
    expect(candidates.every((item) => item.id.isNotEmpty && item.title.isNotEmpty && item.mediaType == 'GAME'), isTrue);
  }, skip: !_runLive, timeout: const Timeout(Duration(minutes: 2)));
}
