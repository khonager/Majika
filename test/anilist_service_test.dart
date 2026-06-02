import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/services/anilist_service.dart';

void main() {
  test('parses public AniList collection entries into normalized media', () {
    final items = AniListService.parseUserCollection({
      'data': {
        'MediaListCollection': {
          'lists': [
            {
              'entries': [
                {
                  'score': 92,
                  'status': 'COMPLETED',
                  'progress': 12,
                  'updatedAt': 100,
                  'media': {
                    'id': 1,
                    'type': 'ANIME',
                    'format': 'TV',
                    'title': {
                      'userPreferred': 'Odd Taxi',
                      'romaji': 'Odd Taxi',
                      'english': 'Odd Taxi',
                    },
                    'coverImage': {
                      'extraLarge': 'https://example.com/cover.jpg',
                    },
                    'genres': ['Mystery', 'Drama'],
                    'siteUrl': 'https://anilist.co/anime/1',
                    'characters': {
                      'nodes': [
                        {
                          'name': {'userPreferred': 'Hiroshi Odokawa'},
                        },
                      ],
                    },
                    'studios': {
                      'nodes': [
                        {'name': 'OLM'},
                      ],
                    },
                    'averageScore': 84,
                    'popularity': 120000,
                    'episodes': 13,
                    'chapters': null,
                    'status': 'FINISHED',
                    'startDate': {'year': 2021},
                    'description': 'A mystery.',
                  },
                },
              ],
            },
          ],
        },
      },
    });

    expect(items, hasLength(1));
    expect(items.first.id, 'anilist_1');
    expect(items.first.title, 'Odd Taxi');
    expect(items.first.rating, 9.2);
    expect(items.first.status, 'COMPLETED');
    expect(items.first.tags, contains('Mystery'));
    expect(items.first.siteUrl, 'https://anilist.co/anime/1');
    expect(items.first.characters, contains('Hiroshi Odokawa'));
    expect(items.first.studios, contains('OLM'));
  });

  test('parses recommendation candidates', () {
    final items = AniListService.parseCandidates({
      'data': {
        'Page': {
          'media': [
            {
              'id': 2,
              'type': 'MANGA',
              'format': 'MANGA',
              'title': {
                'userPreferred': 'Witch Hat Atelier',
                'romaji': 'Tongari Boushi no Atelier',
                'english': 'Witch Hat Atelier',
              },
              'coverImage': {'large': 'https://example.com/manga.jpg'},
              'genres': ['Fantasy'],
              'siteUrl': 'https://anilist.co/manga/2',
              'characters': {
                'nodes': [
                  {
                    'name': {'userPreferred': 'Coco'},
                  },
                ],
              },
              'studios': {'nodes': []},
              'averageScore': 86,
              'popularity': 80000,
              'episodes': null,
              'chapters': null,
              'status': 'RELEASING',
              'startDate': {'year': 2016},
              'description': 'A magical apprenticeship.',
            },
          ],
        },
      },
    });

    expect(items, hasLength(1));
    expect(items.first.mediaType, 'MANGA');
    expect(items.first.rating, 8.6);
    expect(items.first.serviceLabel, 'AniList');
    expect(items.first.siteUrl, 'https://anilist.co/manga/2');
    expect(items.first.characters, contains('Coco'));
  });

  test('parses AniList favorite characters and studios as taste signals', () {
    final signals = AniListService.parseTasteSignals({
      'data': {
        'User': {
          'favourites': {
            'characters': {
              'nodes': [
                {
                  'name': {'userPreferred': 'Coco'},
                },
              ],
            },
            'staff': {
              'nodes': [
                {
                  'name': {'userPreferred': 'Naoko Yamada'},
                },
              ],
            },
            'studios': {
              'nodes': [
                {'name': 'Kyoto Animation'},
              ],
            },
          },
        },
      },
    });

    expect(signals.favoriteCharacters, contains('Coco'));
    expect(signals.favoriteStaff, contains('Naoko Yamada'));
    expect(signals.favoriteStudios, contains('Kyoto Animation'));
  });

  test(
    'search relaxes over-specific AniList tags when no results match',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = AniListService(
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final variables = Map<String, dynamic>.from(
            payload['variables'] as Map,
          );
          requests.add(variables);

          if (variables.containsKey('tagIn')) {
            return _json({
              'data': {
                'Page': {'media': []},
              },
            });
          }

          return _json({
            'data': {
              'Page': {
                'media': [
                  {
                    'id': 10,
                    'type': 'ANIME',
                    'format': 'TV',
                    'title': {
                      'userPreferred': 'Family Comedy',
                      'romaji': 'Family Comedy',
                      'english': null,
                    },
                    'coverImage': {'large': 'https://example.com/family.jpg'},
                    'genres': ['Comedy'],
                    'tags': [
                      {
                        'name': 'Family Life',
                        'rank': 80,
                        'isMediaSpoiler': false,
                        'isAdult': false,
                      },
                    ],
                    'siteUrl': 'https://anilist.co/anime/10',
                    'characters': {'nodes': []},
                    'studios': {'nodes': []},
                    'averageScore': 82,
                    'popularity': 50000,
                    'episodes': 12,
                    'chapters': null,
                    'status': 'FINISHED',
                    'startDate': {'year': 2024},
                    'description': 'A family comedy.',
                  },
                ],
              },
            },
          });
        }),
      );

      final results = await service.searchRecommendationCandidates(
        const RecommendationQuery(
          request:
              'family anime that is good to watch with kids and parents. something fun like spy family',
        ).withInferredSelections(const ['Comedy', 'Family Life', 'Go', 'Kids']),
      );

      expect(results.single.title, 'Family Comedy');
      expect(requests, hasLength(2));
      expect(requests.first['genreIn'], contains('Comedy'));
      expect(requests.first['tagIn'], contains('Family Life'));
      expect(requests.first['tagIn'], isNot(contains('Go')));
      expect(requests.first['tagIn'], isNot(contains('Kids')));
      expect(requests.last, isNot(contains('tagIn')));
    },
  );
}

http.Response _json(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
