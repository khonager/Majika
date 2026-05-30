import 'package:flutter_test/flutter_test.dart';
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
}
