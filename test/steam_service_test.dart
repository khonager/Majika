import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/services/steam_service.dart';

void main() {
  test('parses vanity lookup and public profile summaries', () {
    expect(
      SteamService.parseResolveVanity({
        'response': {'success': 1, 'steamid': '76561198000000000'},
      }),
      '76561198000000000',
    );

    final profile = SteamService.parseUserProfile({
      'response': {
        'players': [
          {
            'steamid': '76561198000000000',
            'personaname': 'tester',
            'avatarfull': 'https://example.com/avatar.jpg',
            'profileurl': 'https://steamcommunity.com/id/tester/',
          },
        ],
      },
    }, fallbackUserName: 'tester');

    expect(profile?.displayName, 'tester');
    expect(profile?.avatarUrl, 'https://example.com/avatar.jpg');
    expect(profile?.profileUrl, contains('steamcommunity.com'));
  });

  test('parses owned, recent, and store-enriched games', () {
    final owned = SteamService.parseOwnedGames({
      'response': {
        'games': [
          {
            'appid': 413150,
            'name': 'Stardew Valley',
            'playtime_forever': 6000,
            'playtime_2weeks': 120,
            'rtime_last_played': 200,
          },
        ],
      },
    });

    expect(owned.single.id, 'steam_413150');
    expect(owned.single.mediaType, 'GAME');
    expect(owned.single.playtimeMinutes, 6000);
    expect(owned.single.status, 'RECENTLY_PLAYED');

    final details = SteamService.parseAppDetails({
      '413150': {
        'success': true,
        'data': {
          'steam_appid': 413150,
          'name': 'Stardew Valley',
          'header_image': 'https://example.com/header.jpg',
          'short_description': 'A farming RPG.',
          'genres': [
            {'description': 'RPG'},
            {'description': 'Simulation'},
          ],
          'categories': [
            {'description': 'Single-player'},
            {'description': 'Full controller support'},
          ],
          'developers': ['ConcernedApe'],
          'metacritic': {'score': 89},
          'release_date': {'date': '26 Feb, 2016'},
        },
      },
    }, appId: 413150);

    expect(details?.title, 'Stardew Valley');
    expect(details?.tags, contains('RPG'));
    expect(details?.tags, contains('Controller Support'));
    expect(details?.format, 'SINGLE_PLAYER');
    expect(details?.rating, 8.9);
    expect(details?.startYear, 2016);
  });

  test('exposes a broad Steam tag catalog for search prompts', () async {
    final service = SteamService();
    final tags = await service.fetchAvailableTags();

    expect(tags, contains('Souls-like'));
    expect(tags, contains('Action RPG'));
    expect(tags, contains('Local Co-Op'));
    expect(tags, contains('Controller Support'));
    expect(tags, contains('Sexual Content'));
    expect(service.supportsAdultContent, isTrue);
    expect(tags, isNot(contains('Mahou Shoujo')));
  });

  test('service resolves vanity and imports public library data', () async {
    final service = SteamService(
      apiKeyProvider: () async => 'test-key',
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('ResolveVanityURL')) {
          return _json({
            'response': {'success': 1, 'steamid': '76561198000000000'},
          });
        }
        if (url.contains('GetOwnedGames')) {
          return _json({
            'response': {
              'game_count': 1,
              'games': [
                {
                  'appid': 646570,
                  'name': 'Slay the Spire',
                  'playtime_forever': 9000,
                },
              ],
            },
          });
        }
        if (url.contains('GetRecentlyPlayedGames')) {
          return _json({
            'response': {
              'games': [
                {
                  'appid': 646570,
                  'name': 'Slay the Spire',
                  'playtime_forever': 9000,
                  'playtime_2weeks': 90,
                  'rtime_last_played': 300,
                },
              ],
            },
          });
        }
        if (url.contains('appdetails')) {
          return _json({
            '646570': {
              'success': true,
              'data': {
                'steam_appid': 646570,
                'name': 'Slay the Spire',
                'genres': [
                  {'description': 'Strategy'},
                  {'description': 'Indie'},
                ],
                'categories': [
                  {'description': 'Single-player'},
                ],
              },
            },
          });
        }
        return http.Response('not found', 404);
      }),
    );

    final library = await service.fetchUserLibrary('tester');

    expect(library.single.title, 'Slay the Spire');
    expect(library.single.tags, contains('Strategy'));
    expect(library.single.playtimeMinutes, 9000);
    expect(library.single.recentPlaytimeMinutes, 90);
  });

  test(
    'niche Steam text search does not append generic baseline when results exist',
    () async {
      final appDetailIds = <String>[];
      final service = SteamService(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.contains('storesearch')) {
            return _json({
              'items': [
                {'id': 1001},
              ],
            });
          }
          if (url.contains('appdetails')) {
            final appId = request.url.queryParameters['appids']!;
            appDetailIds.add(appId);
            return _json({
              appId: {
                'success': true,
                'data': {
                  'steam_appid': int.parse(appId),
                  'name': appId == '1001'
                      ? 'VE GSIM Crane Simulator'
                      : 'Game $appId',
                  'short_description': appId == '1001'
                      ? 'Operate a big crane and complete heavy lifting jobs.'
                      : 'A Steam game.',
                  'genres': [
                    {'description': 'Simulation'},
                  ],
                  'categories': [
                    {'description': 'Single-player'},
                    {'description': 'Full controller support'},
                  ],
                },
              },
            });
          }
          return http.Response('not found', 404);
        }),
      );

      final candidates = await service.searchRecommendationCandidates(
        const RecommendationQuery(
          request: 'a game about operating a big crane',
          mediaTypes: {'GAME'},
          formats: {'SINGLE_PLAYER', 'CONTROLLER'},
        ),
      );

      expect(candidates.map((item) => item.title), ['VE GSIM Crane Simulator']);
      expect(appDetailIds, isNot(contains('413150')));
    },
  );

  test(
    'specific Steam text search does not append generic baseline when no direct results exist',
    () async {
      final appDetailIds = <String>[];
      final service = SteamService(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.contains('storesearch')) {
            return _json({'items': []});
          }
          if (url.contains('appdetails')) {
            final appId = request.url.queryParameters['appids']!;
            appDetailIds.add(appId);
            return _json({
              appId: {
                'success': true,
                'data': {
                  'steam_appid': int.parse(appId),
                  'name': 'Game $appId',
                  'type': 'game',
                  'short_description': 'A Steam game.',
                  'genres': [
                    {'description': 'Simulation'},
                  ],
                  'categories': [
                    {'description': 'Single-player'},
                  ],
                },
              },
            });
          }
          return http.Response('not found', 404);
        }),
      );

      final candidates = await service.searchRecommendationCandidates(
        const RecommendationQuery(
          request:
              'obscure profession simulator with highly specific machinery',
          mediaTypes: {'GAME'},
        ),
      );

      expect(candidates, isEmpty);
      expect(appDetailIds, isEmpty);
    },
  );

  test('Steam app details ignore DLC and map pack store entries', () {
    final item = SteamService.parseAppDetails({
      '1234': {
        'success': true,
        'data': {
          'steam_appid': 1234,
          'type': 'dlc',
          'name': 'Bus Simulator 18 - Official map extension',
          'short_description': 'A DLC map pack.',
        },
      },
    }, appId: 1234);

    expect(item, isNull);
  });

  test('parses Steam adult evidence from content descriptors', () {
    final item = SteamService.parseAppDetails({
      '1126320': {
        'success': true,
        'data': {
          'steam_appid': 1126320,
          'name': 'Being a DIK - Season 1',
          'short_description':
              'A choice-driven adult Visual Novel with romance and drama.',
          'genres': [
            {'description': 'Indie'},
          ],
          'categories': [
            {'description': 'Single-player'},
          ],
          'content_descriptors': {
            'notes': 'The game graphically depicts sex and sexual acts.',
          },
        },
      },
    }, appId: 1126320);

    expect(item?.isAdult, isTrue);
    expect(item?.tags, contains('Sexual Content'));
    expect(item?.tags, contains('Mature'));
    expect(item?.tags, contains('Visual Novel'));
  });

  test('service reports missing local Steam API key', () async {
    final service = SteamService(apiKeyProvider: () async => '');

    expect(service.fetchUserLibrary('tester'), throwsA(isA<SteamException>()));
  });
}

http.Response _json(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
