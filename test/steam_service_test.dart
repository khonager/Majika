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

  test('co-op search adds local co-op candidate pool', () async {
    final service = SteamService(
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('storesearch')) {
          return _json({'items': []});
        }
        if (url.contains('appdetails')) {
          final appId = request.url.queryParameters['appids']!;
          return _json({
            appId: {
              'success': true,
              'data': {
                'steam_appid': int.parse(appId),
                'name': appId == '728880' ? 'Overcooked! 2' : 'Game $appId',
                'genres': [
                  {'description': 'Action'},
                ],
                'categories': [
                  {'description': 'Shared/Split Screen Co-op'},
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
        request: 'fun game to play with two players on one pc with controllers',
        mediaTypes: {'GAME'},
        formats: {'CO_OP', 'CONTROLLER'},
      ),
    );

    expect(candidates.map((item) => item.title), contains('Overcooked! 2'));
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
    'Steam query expansion turns natural language machine requests into simulator search terms',
    () {
      final terms = SteamService.expandedSteamStoreSearchTerms(
        'a game about operating a big crane',
      );

      expect(terms.first, 'a game about operating a big crane');
      expect(terms, contains('operating a big crane'));
      expect(terms, contains('crane'));
      expect(terms, contains('crane simulator'));
      expect(terms, contains('big crane simulator'));
    },
  );

  test('comedy search adds curated matches beyond weak fun titles', () async {
    final storeTerms = <String>[];
    final appDetailIds = <String>[];
    final service = SteamService(
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('storesearch')) {
          storeTerms.add(request.url.queryParameters['term']!);
          return _json({
            'items': [
              {'id': 333},
              {'id': 444},
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
                'name': switch (appId) {
                  '333' => 'Fun with Ragdolls Plus',
                  '444' => 'Funko Fusion',
                  '837470' => 'Untitled Goose Game',
                  '1240210' => 'There Is No Game: Wrong Dimension',
                  _ => 'Game $appId',
                },
                'short_description': switch (appId) {
                  '837470' => 'A silly slapstick sandbox about being a goose.',
                  '1240210' => 'A meta comedy adventure full of jokes.',
                  _ => 'A Steam game.',
                },
                'genres': [
                  {'description': 'Adventure'},
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
        request: 'fun game that makes you laugh a lot',
        aiSelectedTags: {'Comedy', 'Funny'},
        mediaTypes: {'GAME'},
        formats: {'SINGLE_PLAYER'},
      ),
    );

    expect(storeTerms, containsAll(['comedy', 'funny']));
    expect(storeTerms, isNot(contains('fun game that makes you laugh a lot')));
    expect(appDetailIds, contains('837470'));
    expect(appDetailIds, contains('1240210'));
    expect(
      candidates.map((item) => item.title),
      contains('Untitled Goose Game'),
    );
    expect(
      candidates.map((item) => item.title),
      contains('There Is No Game: Wrong Dimension'),
    );
  });

  test('adult search adds curated matches beyond generic title search', () async {
    final storeTerms = <String>[];
    final appDetailIds = <String>[];
    final service = SteamService(
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('storesearch')) {
          storeTerms.add(request.url.queryParameters['term']!);
          return _json({
            'items': [
              {'id': 1145360},
              {'id': 413150},
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
                'name': switch (appId) {
                  '1126320' => 'Being a DIK - Season 1',
                  '611790' => 'House Party',
                  '339800' => 'HuniePop',
                  '1145360' => 'Hades',
                  '413150' => 'Stardew Valley',
                  _ => 'Game $appId',
                },
                'short_description': switch (appId) {
                  '1126320' =>
                    'A choice-driven adult Visual Novel about sex, romance, and drama.',
                  '611790' =>
                    'An edgy comedy adventure with naughty adult situations.',
                  '339800' => 'A dating sim puzzle game with steamy writing.',
                  _ => 'A Steam game.',
                },
                'genres': [
                  {'description': 'Adventure'},
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
        request: 'horny and naughty sexy',
        mediaTypes: {'GAME'},
        formats: {'SINGLE_PLAYER'},
      ),
    );

    expect(
      storeTerms,
      containsAll(['adult', 'hentai', 'dating sim', 'visual novel', 'sexy']),
    );
    expect(storeTerms, isNot(contains('horny and naughty sexy')));
    expect(appDetailIds, contains('1126320'));
    expect(appDetailIds, contains('611790'));
    expect(
      candidates.map((item) => item.title),
      contains('Being a DIK - Season 1'),
    );
    expect(
      candidates.firstWhere((item) => item.id == 'steam_1126320').isAdult,
      isTrue,
    );
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

  test(
    'hidden explicit content suppresses Steam adult candidate search',
    () async {
      final storeTerms = <String>[];
      final appDetailIds = <String>[];
      final service = SteamService(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.contains('storesearch')) {
            storeTerms.add(request.url.queryParameters['term']!);
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
                  'short_description': 'A Steam game.',
                  'genres': [
                    {'description': 'Action'},
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

      await service.searchRecommendationCandidates(
        const RecommendationQuery(
          request: 'horny and naughty sexy',
          excludeAdult: true,
        ),
      );

      expect(storeTerms, isEmpty);
      expect(appDetailIds, isNot(contains('1126320')));
      expect(appDetailIds, isNot(contains('611790')));
    },
  );

  test('inFAMOUS-like search expands to similar Steam candidates', () async {
    final storeTerms = <String>[];
    final appDetailIds = <String>[];
    final service = SteamService(
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('storesearch')) {
          storeTerms.add(request.url.queryParameters['term']!);
          return _json({
            'items': [
              {'id': 10150},
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
                'name': appId == '10150' ? 'Prototype' : 'Game $appId',
                'short_description': 'Open-world superpower action.',
                'genres': [
                  {'description': 'Action'},
                  {'description': 'Adventure'},
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
        request: 'something similar to the infamous games',
      ),
    );

    expect(storeTerms, contains('Prototype'));
    expect(
      storeTerms,
      isNot(contains('something similar to the infamous games')),
    );
    expect(appDetailIds, contains('10150'));
    expect(candidates.map((item) => item.title), contains('Prototype'));
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
