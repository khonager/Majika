import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/recommendations/taste_engine.dart';

void main() {
  test('builds a profile from high-signal library entries', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'anilist_1',
        title: 'Mystery A',
        coverUrl: '',
        tags: const ['Mystery', 'Drama'],
        rating: 9,
        format: 'TV',
        status: 'COMPLETED',
      ),
      MediaItem(
        id: 'anilist_2',
        title: 'Mystery B',
        coverUrl: '',
        tags: const ['Mystery', 'Thriller'],
        rating: 8,
        format: 'TV',
        status: 'CURRENT',
        updatedAt: 200,
      ),
    ]);

    expect(profile.userName, 'tester');
    expect(profile.favoriteGenres.first, 'Mystery');
    expect(profile.completedCount, 1);
    expect(profile.currentCount, 1);
    expect(profile.recentActivity?.title, 'Mystery B');
  });

  test('ranks candidates by taste overlap and excludes library items', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'anilist_1',
        title: 'Seen',
        coverUrl: '',
        tags: const ['Mystery', 'Drama'],
        rating: 9,
        format: 'TV',
        status: 'COMPLETED',
      ),
    ]);

    final recommendations = engine.rankCandidates(profile, [
      MediaItem(
        id: 'anilist_1',
        title: 'Seen',
        coverUrl: '',
        tags: const ['Mystery'],
        format: 'TV',
      ),
      MediaItem(
        id: 'anilist_3',
        title: 'Best Match',
        coverUrl: '',
        tags: const ['Mystery', 'Drama'],
        rating: 8.5,
        format: 'TV',
        popularity: 50000,
      ),
      MediaItem(
        id: 'anilist_4',
        title: 'Weak Match',
        coverUrl: '',
        tags: const ['Sports'],
        rating: 8,
        format: 'MOVIE',
      ),
    ]);

    expect(recommendations, hasLength(2));
    expect(recommendations.first.item.title, 'Best Match');
    expect(recommendations.first.isTopPick, isTrue);
    expect(recommendations.first.signals, contains('Mystery'));
    expect(recommendations.first.matchScore, lessThanOrEqualTo(99));
    expect(recommendations.any((rec) => rec.item.title == 'Seen'), isFalse);
  });

  test('Steam playtime boosts profile tags and game recommendations', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile(
      '76561198000000000',
      [
        MediaItem(
          id: 'steam_1',
          title: 'Played RPG',
          coverUrl: '',
          tags: const ['RPG', 'Strategy'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          status: 'OWNED',
          playtimeMinutes: 6000,
          sourceId: 'com.majika.service.steam',
        ),
        MediaItem(
          id: 'steam_2',
          title: 'Barely Played Puzzle',
          coverUrl: '',
          tags: const ['Puzzle'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          status: 'OWNED',
          playtimeMinutes: 20,
          sourceId: 'com.majika.service.steam',
        ),
      ],
      serviceId: 'com.majika.service.steam',
      serviceName: 'Steam',
    );

    final recommendations = engine.rankCandidates(profile, [
      MediaItem(
        id: 'steam_3',
        title: 'Strategy RPG Match',
        coverUrl: '',
        tags: const ['RPG', 'Strategy'],
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        sourceId: 'com.majika.service.steam',
      ),
      MediaItem(
        id: 'steam_4',
        title: 'Puzzle Match',
        coverUrl: '',
        tags: const ['Puzzle'],
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        sourceId: 'com.majika.service.steam',
      ),
    ]);

    expect(profile.serviceName, 'Steam');
    expect(profile.favoriteGenres.first, 'RPG');
    expect(recommendations.first.item.title, 'Strategy RPG Match');
  });

  test(
    'ratings and AniList favorites affect match scores without flat 99s',
    () {
      final engine = TasteEngine();
      final profile = engine.buildProfile(
        'tester',
        [
          MediaItem(
            id: 'anilist_1',
            title: 'Loved Mystery',
            coverUrl: '',
            tags: const ['Mystery', 'Drama'],
            rating: 10,
            format: 'TV',
            status: 'COMPLETED',
            characters: const ['Coco'],
            studios: const ['Kyoto Animation'],
          ),
          MediaItem(
            id: 'anilist_2',
            title: 'Dropped Sports',
            coverUrl: '',
            tags: const ['Sports'],
            rating: 3,
            format: 'TV',
            status: 'DROPPED',
          ),
        ],
        signals: const UserTasteSignals(
          favoriteCharacters: ['Coco'],
          favoriteStudios: ['Kyoto Animation'],
        ),
      );

      final recommendations = engine.rankCandidates(profile, [
        MediaItem(
          id: 'anilist_3',
          title: 'Favorite Signal Match',
          coverUrl: '',
          tags: const ['Mystery'],
          rating: 8.8,
          format: 'TV',
          characters: const ['Coco'],
          studios: const ['Kyoto Animation'],
          popularity: 80000,
        ),
        MediaItem(
          id: 'anilist_4',
          title: 'Low Signal Match',
          coverUrl: '',
          tags: const ['Sports'],
          rating: 8.8,
          format: 'MOVIE',
          popularity: 10000,
        ),
      ]);

      expect(recommendations.first.item.title, 'Favorite Signal Match');
      expect(recommendations.first.signals, contains('favorite Coco'));
      expect(
        recommendations.first.signals,
        contains('favorite studio Kyoto Animation'),
      );
      expect(
        recommendations.first.matchScore,
        greaterThan(recommendations.last.matchScore),
      );
      expect(
        recommendations.map((rec) => rec.matchScore).toSet(),
        hasLength(2),
      );
    },
  );

  test('search query filters by requested tag, format, and media type', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'anilist_1',
        title: 'Seen',
        coverUrl: '',
        tags: const ['Mystery'],
        rating: 9,
        format: 'TV',
        status: 'COMPLETED',
      ),
    ]);

    final recommendations = engine.rankCandidates(
      profile,
      [
        MediaItem(
          id: 'anilist_2',
          title: 'Mystery Movie',
          coverUrl: '',
          tags: const ['Mystery', 'Drama'],
          rating: 8,
          format: 'MOVIE',
          mediaType: 'ANIME',
        ),
        MediaItem(
          id: 'anilist_3',
          title: 'Mystery Manga',
          coverUrl: '',
          tags: const ['Mystery'],
          rating: 8,
          format: 'MANGA',
          mediaType: 'MANGA',
        ),
      ],
      query: const RecommendationQuery(
        request: 'find a mystery movie',
        selectedTags: {'Mystery'},
        formats: {'MOVIE'},
        mediaTypes: {'ANIME'},
      ),
    );

    expect(recommendations, hasLength(1));
    expect(recommendations.first.item.title, 'Mystery Movie');
    expect(recommendations.first.reason, contains('find a mystery movie'));
  });

  test('adult content is excluded unless query opts in or asks for it', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'anilist_1',
        title: 'Seen',
        coverUrl: '',
        tags: const ['Romance'],
        rating: 8,
        format: 'TV',
      ),
    ]);
    final candidates = [
      MediaItem(
        id: 'anilist_2',
        title: 'Adult Romance',
        coverUrl: '',
        tags: const ['Romance'],
        rating: 8,
        format: 'OVA',
        isAdult: true,
      ),
    ];

    expect(engine.rankCandidates(profile, candidates), isEmpty);
    expect(
      engine.rankCandidates(
        profile,
        candidates,
        query: const RecommendationQuery(request: 'hentai romance ova'),
      ),
      hasLength(1),
    );
  });

  test(
    'request interpretation infers tags and formats from natural language',
    () {
      final timeTravelMovie = const RecommendationQuery(
        request: 'romance movie about time travel',
      ).withInferredSelections(RecommendationQuery.browsableTags);

      expect(timeTravelMovie.selectedTags, isEmpty);
      expect(timeTravelMovie.aiSelectedTags, contains('Romance'));
      expect(timeTravelMovie.aiSelectedTags, contains('Time Manipulation'));
      expect(timeTravelMovie.formats, contains('MOVIE'));
      expect(timeTravelMovie.mediaTypes, contains('ANIME'));

      final obsessedCharacter = const RecommendationQuery(
        request: 'obsessed character thriller',
      ).withInferredSelections(RecommendationQuery.browsableTags);

      expect(obsessedCharacter.aiSelectedTags, contains('Yandere'));
      expect(obsessedCharacter.aiSelectedTags, contains('Thriller'));

      final magicSchool = const RecommendationQuery(
        request: 'like harry potter',
      ).withInferredSelections(const ['Fantasy', 'Magic', 'School']);

      expect(magicSchool.aiSelectedTags, contains('Fantasy'));
      expect(magicSchool.aiSelectedTags, contains('Magic'));
      expect(magicSchool.aiSelectedTags, contains('School'));
    },
  );

  test('harry potter-like requests prefer magic school candidates', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'anilist_1',
        title: 'Seen Action Show',
        coverUrl: '',
        tags: const ['Action', 'Male Protagonist'],
        rating: 9,
        format: 'TV',
        status: 'COMPLETED',
      ),
    ]);

    final recommendations = engine.rankCandidates(
      profile,
      [
        MediaItem(
          id: 'anilist_2',
          title: 'Tensei Shitara Slime Datta Ken 4th Season',
          coverUrl: '',
          tags: const [
            'Action',
            'Adventure',
            'Comedy',
            'Fantasy',
            'Isekai',
            'Magic',
            'Male Protagonist',
          ],
          rating: 8.8,
          format: 'TV',
          mediaType: 'ANIME',
        ),
        MediaItem(
          id: 'anilist_3',
          title: 'Tsue to Tsurugi no Wistoria Season 2',
          coverUrl: '',
          tags: const [
            'Action',
            'Adventure',
            'Drama',
            'Fantasy',
            'Magic',
            'School',
            'Swordplay',
            'Male Protagonist',
          ],
          rating: 8.3,
          format: 'TV',
          mediaType: 'ANIME',
        ),
        MediaItem(
          id: 'anilist_4',
          title: 'MASHLE: MAGIC AND MUSCLES',
          coverUrl: '',
          tags: const [
            'Action',
            'Comedy',
            'Fantasy',
            'Magic',
            'School',
            'Super Power',
            'Male Protagonist',
          ],
          rating: 8.1,
          format: 'TV',
          mediaType: 'ANIME',
        ),
      ],
      query: const RecommendationQuery(
        request: 'like harry potter',
        aiSelectedTags: {'Drama', 'Adventure'},
      ),
    );

    expect(recommendations.first.item.title, isNot(contains('Slime')));
    expect(
      recommendations.first.item.tags,
      containsAll(<String>['Magic', 'School']),
    );
  });

  test(
    'new searches clear stale AI selected tags while keeping pinned tags',
    () {
      final firstQuery = const RecommendationQuery(
        request: 'romance movie about time travel',
        selectedTags: {'Mystery'},
      ).withInferredSelections(RecommendationQuery.browsableTags);

      final secondQuery = firstQuery
          .copyWith(request: 'sports anime', aiSelectedTags: {})
          .withInferredSelections(RecommendationQuery.browsableTags);

      expect(secondQuery.selectedTags, contains('Mystery'));
      expect(secondQuery.aiSelectedTags, isNot(contains('Time Manipulation')));
      expect(secondQuery.aiSelectedTags, contains('Sports'));
    },
  );
}
