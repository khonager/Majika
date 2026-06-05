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

  test('Steam mode requests require every requested capability', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile(
      '76561198000000000',
      [
        MediaItem(
          id: 'steam_1',
          title: 'Played Action Game',
          coverUrl: '',
          tags: const ['Action', 'Controller Support'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          status: 'OWNED',
          playtimeMinutes: 6000,
          sourceId: 'com.majika.service.steam',
        ),
      ],
      serviceId: 'com.majika.service.steam',
      serviceName: 'Steam',
    );

    final recommendations = engine.rankCandidates(
      profile,
      [
        MediaItem(
          id: 'steam_gta',
          title: 'Single Player Controller Game',
          coverUrl: '',
          tags: const [
            'Action',
            'Adventure',
            'Co-op',
            'Online Co-op',
            'Controller Support',
          ],
          rating: 9.3,
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
          popularity: 100000,
        ),
        MediaItem(
          id: 'steam_coop',
          title: 'Couch Co-op Controller Game',
          coverUrl: '',
          tags: const [
            'Action',
            'Co-op',
            'Shared/Split Screen Co-op',
            'Controller Support',
          ],
          rating: 8.1,
          format: 'CO_OP',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(
        request: 'fun game to play with two players on one pc with controller',
        mediaTypes: {'GAME'},
        formats: {'MULTIPLAYER', 'CO_OP'},
      ),
    );

    expect(recommendations, hasLength(1));
    expect(recommendations.single.item.id, 'steam_coop');
  });

  test('Steam comedy searches reject weak title-only fun matches', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile(
      '76561198000000000',
      [
        MediaItem(
          id: 'steam_owned',
          title: 'Played Action Game',
          coverUrl: '',
          tags: const ['Action', 'Single-player', 'Controller Support'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          status: 'OWNED',
          playtimeMinutes: 6000,
          sourceId: 'com.majika.service.steam',
        ),
      ],
      serviceId: 'com.majika.service.steam',
      serviceName: 'Steam',
    );

    final recommendations = engine.rankCandidates(
      profile,
      [
        MediaItem(
          id: 'steam_title_only',
          title: 'Community College Hero: Fun and Games',
          coverUrl: '',
          tags: const ['Adventure', 'Indie', 'Single-player'],
          description:
              'Join heroes-in-training as they enjoy a tabletop campaign.',
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
        MediaItem(
          id: 'steam_gta',
          title: 'Grand Theft Auto V Legacy',
          coverUrl: '',
          tags: const ['Action', 'Adventure', 'Single-player'],
          description: 'Explore Los Santos and Blaine County.',
          rating: 9.5,
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          popularity: 100000,
          sourceId: 'com.majika.service.steam',
        ),
        MediaItem(
          id: 'steam_ragdolls',
          title: 'Fun with Ragdolls Plus',
          coverUrl: '',
          tags: const ['Action', 'Adventure', 'Single-player'],
          description:
              'A 3D physics platformer with a cinematic story and sandbox chaos.',
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          popularity: 100000,
          sourceId: 'com.majika.service.steam',
        ),
        MediaItem(
          id: 'steam_funko',
          title: 'Funko Fusion',
          coverUrl: '',
          tags: const ['Action', 'Adventure', 'Single-player'],
          description:
              'A festival of fandom with iconic worlds and mashup characters.',
          rating: 8.8,
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          popularity: 100000,
          sourceId: 'com.majika.service.steam',
        ),
        MediaItem(
          id: 'steam_comedy',
          title: 'There Is No Game: Wrong Dimension',
          coverUrl: '',
          tags: const ['Adventure', 'Single-player'],
          description:
              'A hilarious meta comedy adventure full of jokes and absurd surprises.',
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
        MediaItem(
          id: 'steam_tagged',
          title: 'Comedy Night',
          coverUrl: '',
          tags: const ['Comedy', 'Funny', 'Single-player'],
          description: 'Perform jokes for a live audience.',
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(
        request: 'fun game that makes you laugh a lot',
        aiSelectedTags: {'Comedy', 'Funny'},
        mediaTypes: {'GAME'},
        formats: {'SINGLE_PLAYER'},
      ),
    );

    final ids = recommendations.map((recommendation) => recommendation.item.id);
    expect(ids, containsAll(['steam_comedy', 'steam_tagged']));
    expect(ids, isNot(contains('steam_title_only')));
    expect(ids, isNot(contains('steam_gta')));
    expect(ids, isNot(contains('steam_ragdolls')));
    expect(ids, isNot(contains('steam_funko')));
    expect(
      recommendations.map((recommendation) => recommendation.matchScore),
      everyElement(lessThan(99)),
    );
  });

  test('inFAMOUS-like game requests infer open-world action traits', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile(
      '76561198000000000',
      const [],
      serviceId: 'com.majika.service.steam',
      serviceName: 'Steam',
    );
    final query = const RecommendationQuery(
      request: 'something similar to the infamous games',
    ).withInferredSelections(RecommendationQuery.browsableTags);

    expect(query.aiSelectedTags, contains('Action'));
    expect(query.aiSelectedTags, contains('Adventure'));
    expect(query.aiSelectedTags, contains('Open World'));
    expect(query.formats, contains('SINGLE_PLAYER'));
    expect(query.mediaTypes, contains('GAME'));

    final recommendations = engine.rankCandidates(profile, [
      MediaItem(
        id: 'steam_10150',
        title: 'Prototype',
        coverUrl: '',
        tags: const ['Action', 'Adventure', 'Open World', 'Supernatural'],
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        rating: 8.1,
      ),
      MediaItem(
        id: 'steam_2',
        title: 'Quiet Puzzle',
        coverUrl: '',
        tags: const ['Puzzle'],
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        rating: 9,
      ),
    ], query: query);

    expect(recommendations.single.item.title, 'Prototype');
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
    expect(
      engine.rankCandidates(
        profile,
        candidates,
        query: const RecommendationQuery(
          request: 'hentai romance ova',
          excludeAdult: true,
        ),
      ),
      isEmpty,
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

      final legacySeries = const RecommendationQuery(
        formats: {'TV', 'OVA', 'ONA', 'SPECIAL'},
      );
      expect(legacySeries.effectiveFormats(), {'SERIES'});
      expect(legacySeries.effectiveMediaTypes(), {'ANIME'});

      final book = const RecommendationQuery(
        request: 'recommend a fantasy book',
      ).withInferredSelections(RecommendationQuery.browsableTags);
      expect(book.formats, contains('BOOK'));
      expect(book.mediaTypes, contains('MANGA'));

      const mangaFormatWins = RecommendationQuery(
        mediaTypes: {'ANIME'},
        formats: {'MANGA'},
      );
      expect(mangaFormatWins.effectiveMediaTypes(), {'MANGA'});

      final aniListRequest = const RecommendationQuery(
        request: 'anime recommendation for beginners',
      ).withInferredSelections(RecommendationQuery.aniListBrowsableTags);
      expect(aniListRequest.aiSelectedTags, isNot(contains('Anime')));

      final adultRequest = const RecommendationQuery(
        request: 'an erotic adult anime',
      ).withInferredSelections(const ['Romance', 'Hentai']);
      expect(adultRequest.includeAdult, isTrue);
      expect(adultRequest.aiSelectedTags, contains('Hentai'));

      final hiddenAdultRequest = const RecommendationQuery(
        request: 'an erotic adult anime',
        excludeAdult: true,
      ).withInferredSelections(const ['Romance', 'Hentai']);
      expect(hiddenAdultRequest.includeAdult, isFalse);
      expect(hiddenAdultRequest.allowsAdult, isFalse);

      final broadBeginnerRequest = const RecommendationQuery(
        request: 'something good for a person who never watched anime ever',
      );
      expect(
        broadBeginnerRequest.matchesText(
          MediaItem(
            id: 'anilist_beginner',
            title: 'Approachable Pick',
            coverUrl: '',
            tags: ['Comedy'],
            format: 'TV',
          ),
        ),
        isTrue,
      );

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

      final familyAnime = const RecommendationQuery(
        request:
            'family anime that is good to watch with kids and parents. something fun like spy family',
      ).withInferredSelections(const ['Comedy', 'Family Life', 'Go', 'Kids']);

      expect(familyAnime.aiSelectedTags, contains('Comedy'));
      expect(familyAnime.aiSelectedTags, contains('Family Life'));
      expect(familyAnime.aiSelectedTags, isNot(contains('Go')));
      expect(familyAnime.aiSelectedTags, isNot(contains('Kids')));

      final specificRelationship =
          const RecommendationQuery(
            request: 'a romance between two males in school anime',
          ).withInferredSelections(const [
            'Romance',
            "Boys' Love",
            'LGBTQ+ Themes',
            'School',
          ]);

      expect(specificRelationship.aiSelectedTags, contains('Romance'));
      expect(specificRelationship.aiSelectedTags, contains("Boys' Love"));
      expect(specificRelationship.aiSelectedTags, contains('School'));
      expect(
        specificRelationship.specificRequestedTags(const [
          'Romance',
          "Boys' Love",
          'LGBTQ+ Themes',
          'School',
        ]),
        contains("Boys' Love"),
      );
      expect(
        specificRelationship.specificRequestedTags(const [
          'Romance',
          "Boys' Love",
          'LGBTQ+ Themes',
          'School',
        ]),
        isNot(contains('School')),
      );

      final couchCoopGame = const RecommendationQuery(
        request: 'two players on one pc with controller',
        formats: {'CO_OP'},
      ).withInferredSelections(RecommendationQuery.browsableTags);

      expect(couchCoopGame.formats, contains('CO_OP'));
      expect(couchCoopGame.formats, contains('CONTROLLER'));
      expect(couchCoopGame.infersLocalCoOp, isTrue);
      expect(couchCoopGame.effectiveFormats(), contains('CO_OP'));
      expect(couchCoopGame.mediaTypes, contains('GAME'));
    },
  );

  test('specific inferred tags filter broad-only matches', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'anilist_seen',
        title: 'Seen Romance',
        coverUrl: '',
        tags: const ['Romance', 'School'],
        rating: 9.5,
        format: 'TV',
        status: 'COMPLETED',
      ),
    ]);

    final recommendations = engine.rankCandidates(
      profile,
      [
        MediaItem(
          id: 'anilist_generic',
          title: 'Generic School Romance',
          coverUrl: '',
          tags: const ['Romance', 'School', 'Heterosexual'],
          rating: 9.8,
          format: 'TV',
          mediaType: 'ANIME',
        ),
        MediaItem(
          id: 'anilist_specific',
          title: 'Specific Relationship Story',
          coverUrl: '',
          tags: const ['Romance', 'School', "Boys' Love"],
          rating: 7.1,
          format: 'TV',
          mediaType: 'ANIME',
        ),
      ],
      query: const RecommendationQuery(
        request: 'a romance between two males in school anime',
      ),
    );

    expect(recommendations, hasLength(1));
    expect(recommendations.single.item.title, 'Specific Relationship Story');
  });

  test('Steam AI-selected broad tags keep candidates with request evidence', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'steam_seen',
        title: 'Seen Controller Game',
        coverUrl: '',
        tags: const ['Action', 'Single-player', 'Controller Support'],
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        sourceId: 'com.majika.service.steam',
        status: 'OWNED',
      ),
    ]);

    final recommendations = engine.rankCandidates(
      profile,
      [
        MediaItem(
          id: 'steam_candidate',
          title: 'Mischief Village',
          coverUrl: '',
          tags: const ['Action', 'Adventure', 'Single-player'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
          description:
              'A silly slapstick comedy about causing playful chaos in a small village.',
        ),
      ],
      query: const RecommendationQuery(
        request: 'fun game that makes you laugh a lot',
        aiSelectedTags: {'Comedy', 'Funny'},
        formats: {'SINGLE_PLAYER'},
      ),
    );

    expect(recommendations, hasLength(1));
    expect(recommendations.single.item.title, 'Mischief Village');
  });

  test('low-signal fun words do not boost title-only matches', () {
    final engine = TasteEngine();
    final profile = engine.buildProfile('tester', [
      MediaItem(
        id: 'steam_seen',
        title: 'Seen Action Game',
        coverUrl: '',
        tags: const ['Action'],
        format: 'SINGLE_PLAYER',
        mediaType: 'GAME',
        status: 'OWNED',
        sourceId: 'com.majika.service.steam',
      ),
    ], serviceName: 'Steam');

    final recommendations = engine.rankCandidates(
      profile,
      [
        MediaItem(
          id: 'steam_funnel',
          title: 'Funnel Runners',
          coverUrl: '',
          tags: const ['Action', 'Single-player'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
          description: 'A co-op survival game with escalating disasters.',
        ),
        MediaItem(
          id: 'steam_fun',
          title: "Lovers' Fun!",
          coverUrl: '',
          tags: const ['Casual', 'Single-player'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
          description: 'A light simulation about an absurd sudden proposal.',
        ),
      ],
      query: const RecommendationQuery(
        request: 'fun game',
        formats: {'SINGLE_PLAYER'},
      ),
    );

    expect(recommendations.first.item.title, 'Funnel Runners');
    expect(
      recommendations.map((rec) => rec.item.title),
      contains("Lovers' Fun!"),
    );
  });

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
