import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/services/media_service.dart';

class TestMediaService implements MediaService {
  @override
  String get displayName => 'AniList';

  @override
  String get id => 'com.majika.service.anilist';

  @override
  String get connectTitle => 'Connect AniList';

  @override
  String get connectDescription => 'Enter a public AniList username.';

  @override
  String get userNameHint => 'AniList username';

  @override
  String get userNameEmptyMessage => 'Enter an AniList username first.';

  @override
  String get importButtonLabel => 'Build profile';

  @override
  String get searchPlaceholder => 'Search a vibe, tag, format, or request';

  @override
  String get openTooltipLabel => 'Open on AniList';

  @override
  List<String> get supportedMediaTypes => RecommendationQuery.aniListMediaTypes;

  @override
  List<String> get supportedFormats => RecommendationQuery.aniListFormats;

  @override
  bool get supportsAdultContent => true;

  @override
  Future<ServiceUserProfile?> fetchUserProfile(String userName) async {
    return ServiceUserProfile(userName: userName);
  }

  @override
  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  }) async {
    return [
      MediaItem(
        id: 'anilist_2',
        title: 'Best Match',
        coverUrl: '',
        tags: const ['Mystery', 'Drama'],
        rating: 8.5,
        format: 'TV',
        popularity: 50000,
        startYear: DateTime.now().year,
        siteUrl: 'https://anilist.co/anime/2',
        description: 'A distinct mystery drama about one tense case.',
      ),
      MediaItem(
        id: 'anilist_3',
        title: 'Another Match',
        coverUrl: '',
        tags: const ['Mystery'],
        rating: 8,
        format: 'MOVIE',
        siteUrl: 'https://anilist.co/anime/3',
        description: 'A separate movie mystery with its own premise.',
      ),
      if (includeAdult)
        MediaItem(
          id: 'anilist_4',
          title: 'Adult Match',
          coverUrl: '',
          tags: const ['Romance'],
          rating: 7.8,
          format: 'OVA',
          mediaType: 'ANIME',
          isAdult: true,
          siteUrl: 'https://anilist.co/anime/4',
        ),
    ];
  }

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) async {
    final tags = query.effectiveTags(await fetchAvailableTags());
    return [
      if (tags.contains('Time Manipulation'))
        MediaItem(
          id: 'anilist_5',
          title: 'Time Travel Movie',
          coverUrl: '',
          tags: const ['Romance', 'Time Manipulation'],
          rating: 8.4,
          format: 'MOVIE',
          mediaType: 'ANIME',
          siteUrl: 'https://anilist.co/anime/5',
          description:
              'A romance movie where time travel changes the relationship.',
        ),
      ...await fetchRecommendationCandidates(includeAdult: query.allowsAdult),
    ];
  }

  @override
  Future<List<String>> fetchAvailableTags() async {
    return const [
      'Drama',
      'Mystery',
      'Romance',
      'Time Manipulation',
      'Yandere',
    ];
  }

  @override
  Future<UserTasteSignals> fetchTasteSignals(String userName) async {
    return const UserTasteSignals(
      favoriteCharacters: ['Odokawa'],
      favoriteStudios: ['OLM'],
    );
  }

  @override
  Future<List<MediaItem>> fetchUserLibrary(String userName) async {
    return [
      MediaItem(
        id: 'anilist_1',
        title: 'Seen Mystery',
        coverUrl: '',
        tags: const ['Mystery', 'Drama'],
        rating: 9,
        format: 'TV',
        status: 'CURRENT',
        updatedAt: 100,
        characters: const ['Odokawa'],
        studios: const ['OLM'],
        siteUrl: 'https://anilist.co/anime/1',
      ),
    ];
  }
}

