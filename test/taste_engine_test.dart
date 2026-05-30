import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
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
    expect(recommendations.any((rec) => rec.item.title == 'Seen'), isFalse);
  });

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

      expect(timeTravelMovie.selectedTags, contains('Romance'));
      expect(timeTravelMovie.selectedTags, contains('Time Manipulation'));
      expect(timeTravelMovie.formats, contains('MOVIE'));
      expect(timeTravelMovie.mediaTypes, contains('ANIME'));

      final obsessedCharacter = const RecommendationQuery(
        request: 'obsessed character thriller',
      ).withInferredSelections(RecommendationQuery.browsableTags);

      expect(obsessedCharacter.selectedTags, contains('Yandere'));
      expect(obsessedCharacter.selectedTags, contains('Thriller'));
    },
  );
}
