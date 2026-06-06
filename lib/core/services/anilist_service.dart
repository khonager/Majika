import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/services/media_service.dart';

class AniListService implements MediaService {
  AniListService({http.Client? client}) : _client = client ?? http.Client();

  static const endpoint = 'https://graphql.anilist.co';
  static const sourceId = 'com.majika.service.anilist';

  final http.Client _client;
  List<String>? _availableTagsCache;

  @override
  String get id => sourceId;

  @override
  String get displayName => 'AniList';

  @override
  String get connectTitle => 'Connect AniList';

  @override
  String get connectDescription =>
      'Enter a public AniList username. Majika will read anime and manga lists, build a local taste profile, then rank current releases against it.';

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
    return ServiceUserProfile(
      userName: userName,
      profileUrl: 'https://anilist.co/user/$userName',
    );
  }

  @override
  Future<List<MediaItem>> fetchUserLibrary(String userName) async {
    final anime = await _fetchUserCollection(userName, 'ANIME');
    final manga = await _fetchUserCollection(userName, 'MANGA');
    return [...anime, ...manga];
  }

  @override
  Future<UserTasteSignals> fetchTasteSignals(String userName) async {
    final response = await _postGraphQl(_tasteSignalsQuery, {
      'userName': userName,
    });
    return parseTasteSignals(jsonDecode(response.body));
  }

  @override
  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  }) async {
    final anime = await _fetchCandidates('ANIME', includeAdult: includeAdult);
    final manga = await _fetchCandidates('MANGA', includeAdult: includeAdult);
    return [...anime, ...manga];
  }

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) async {
    final mediaTypes = query.effectiveMediaTypes();
    final typesToSearch = mediaTypes.isEmpty
        ? RecommendationQuery.aniListMediaTypes
        : mediaTypes
              .where(RecommendationQuery.aniListMediaTypes.contains)
              .toList();
    if (typesToSearch.isEmpty) return [];

    final availableTags = await fetchAvailableTags();
    final results = <MediaItem>[];

    for (final type in typesToSearch) {
      results.addAll(
        await _searchCandidates(type, query, availableTags: availableTags),
      );
    }

    return _dedupe(results);
  }

  @override
  Future<List<String>> fetchAvailableTags() async {
    final cachedTags = _availableTagsCache;
    if (cachedTags != null) return cachedTags;

    final response = await _postGraphQl(_tagsQuery, const {});
    final decoded = jsonDecode(response.body);
    final tags = <String>[
      ...List<String>.from(decoded['data']?['GenreCollection'] ?? const []),
    ];
    final mediaTags = decoded['data']?['MediaTagCollection'];
    if (mediaTags is List) {
      for (final tag in mediaTags) {
        final name = tag is Map ? tag['name']?.toString() : null;
        if (name != null && name.trim().isNotEmpty) {
          tags.add(name);
        }
      }
    }

    tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final availableTags = tags.toSet().toList();
    _availableTagsCache = availableTags;
    return availableTags;
  }

  Future<List<MediaItem>> _fetchUserCollection(
    String userName,
    String mediaType,
  ) async {
    final response = await _postGraphQl(_userCollectionQuery, {
      'userName': userName,
      'type': mediaType,
    });
    return parseUserCollection(jsonDecode(response.body));
  }

  Future<List<MediaItem>> _fetchCandidates(
    String mediaType, {
    required bool includeAdult,
  }) async {
    final response = await _postGraphQl(_candidateQuery, {
      'type': mediaType,
      'page': 1,
      'perPage': mediaType == 'ANIME' ? 24 : 16,
      'isAdult': includeAdult,
    });
    return parseCandidates(jsonDecode(response.body));
  }

  Future<List<MediaItem>> _searchCandidates(
    String mediaType,
    RecommendationQuery query, {
    required Iterable<String> availableTags,
  }) async {
    final formats = RecommendationQuery.aniListReleaseFormatsFor(
      query.effectiveFormats(),
    );
    final tags = query.effectiveTags(availableTags);
    final searchText = tags.isEmpty && formats.isEmpty
        ? query.aniListSearchText
        : '';
    final genreTags = tags.where(_knownAniListGenres.contains).toList();
    final mediaTags = tags
        .where((tag) => !_knownAniListGenres.contains(tag))
        .toList();
    final variables = <String, dynamic>{
      'type': mediaType,
      'page': 1,
      'perPage': 50,
      'isAdult': query.allowsAdult,
      if (searchText.isNotEmpty) 'search': searchText,
      if (formats.isNotEmpty) 'formatIn': formats.toList(),
      if (genreTags.isNotEmpty) 'genreIn': genreTags,
      if (mediaTags.isNotEmpty) 'tagIn': mediaTags,
    };

    final pageCount = tags.isEmpty && searchText.isEmpty ? 4 : 1;
    final candidates = await _searchPages(variables, pageCount: pageCount);
    if (candidates.isNotEmpty || mediaTags.isEmpty || genreTags.isEmpty) {
      return candidates;
    }

    final relaxedVariables = {...variables}..remove('tagIn');
    return _searchPages(relaxedVariables, pageCount: pageCount);
  }

  Future<List<MediaItem>> _searchPages(
    Map<String, dynamic> variables, {
    required int pageCount,
  }) async {
    final candidates = <MediaItem>[];
    for (var page = 1; page <= pageCount; page++) {
      final response = await _postGraphQl(_searchQuery, {
        ...variables,
        'page': page,
      });
      final pageCandidates = parseCandidates(jsonDecode(response.body));
      if (pageCandidates.isEmpty) break;
      candidates.addAll(pageCandidates);
    }
    return _dedupe(candidates);
  }

  Future<http.Response> _postGraphQl(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await _client.post(
      Uri.parse(endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Majika/1.0',
      },
      body: jsonEncode({'query': query, 'variables': variables}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AniListException(
        'AniList returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['errors'] is List) {
      final errors = decoded['errors'] as List;
      final message = errors.isEmpty
          ? 'Unknown AniList GraphQL error.'
          : (errors.first as Map?)?['message']?.toString() ??
                'Unknown AniList GraphQL error.';
      throw AniListException(message);
    }

    return response;
  }

  static List<MediaItem> parseUserCollection(Map<String, dynamic> json) {
    final collection = json['data']?['MediaListCollection'];
    final lists = collection?['lists'];
    if (lists is! List) return [];

    final items = <MediaItem>[];
    for (final list in lists) {
      final entries = list is Map ? list['entries'] : null;
      if (entries is! List) continue;

      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) continue;
        final media = entry['media'];
        if (media is! Map<String, dynamic>) continue;
        items.add(_mediaFromAniList(media, entry: entry));
      }
    }

    return _dedupe(items);
  }

  static List<MediaItem> parseCandidates(Map<String, dynamic> json) {
    final media = json['data']?['Page']?['media'];
    if (media is! List) return [];

    return _dedupe(
      media
          .whereType<Map<String, dynamic>>()
          .map((item) => _mediaFromAniList(item))
          .toList(),
    );
  }

  static UserTasteSignals parseTasteSignals(Map<String, dynamic> json) {
    final favourites = json['data']?['User']?['favourites'];
    if (favourites is! Map) return UserTasteSignals.empty;

    return UserTasteSignals(
      favoriteCharacters: _namesFromNodes(
        favourites['characters']?['nodes'],
        nestedName: true,
      ),
      favoriteStaff: _namesFromNodes(
        favourites['staff']?['nodes'],
        nestedName: true,
      ),
      favoriteStudios: _namesFromNodes(favourites['studios']?['nodes']),
    );
  }

  static List<MediaItem> _dedupe(List<MediaItem> items) {
    final seen = <String>{};
    final deduped = <MediaItem>[];

    for (final item in items) {
      if (seen.add(item.id)) {
        deduped.add(item);
      }
    }

    return deduped;
  }

  static MediaItem _mediaFromAniList(
    Map<String, dynamic> media, {
    Map<String, dynamic>? entry,
  }) {
    final title = media['title'];
    final coverImage = media['coverImage'];
    final startDate = media['startDate'];
    final score = entry?['score'] ?? media['averageScore'];
    final progress = entry?['progress'];
    final format = media['format']?.toString() ?? 'UNKNOWN';
    final type = media['type']?.toString() ?? 'ANIME';
    final totalUnits = type == 'MANGA' ? media['chapters'] : media['episodes'];

    return MediaItem(
      id: 'anilist_${media['id']}',
      title:
          title?['userPreferred']?.toString() ??
          title?['english']?.toString() ??
          title?['romaji']?.toString() ??
          'Untitled',
      coverUrl:
          coverImage?['extraLarge']?.toString() ??
          coverImage?['large']?.toString() ??
          '',
      tags: _tagsFromMedia(media),
      rating: score is num && score > 0 ? score.toDouble() / 10 : null,
      subtitle: _subtitleFor(type, format, totalUnits, progress),
      extensionId: sourceId,
      sourceId: sourceId,
      mediaType: type,
      format: format,
      status: entry?['status']?.toString() ?? media['status']?.toString(),
      description: media['description']?.toString(),
      siteUrl: media['siteUrl']?.toString() ?? '',
      characters: _namesFromNodes(
        media['characters']?['nodes'],
        nestedName: true,
      ),
      studios: _namesFromNodes(media['studios']?['nodes']),
      startYear: startDate is Map ? startDate['year'] as int? : null,
      popularity: media['popularity'] as int?,
      updatedAt: entry?['updatedAt'] as int?,
      isAdult: media['isAdult'] as bool? ?? false,
    );
  }

  static List<String> _tagsFromMedia(Map<String, dynamic> media) {
    final tags = <String>[...List<String>.from(media['genres'] ?? const [])];
    final mediaTags = media['tags'];
    if (mediaTags is List) {
      for (final tag in mediaTags) {
        final name = tag is Map ? tag['name']?.toString() : null;
        final rank = tag is Map ? tag['rank'] as int? : null;
        final spoiler = tag is Map ? tag['isMediaSpoiler'] == true : false;
        if (name != null && !spoiler && (rank == null || rank >= 35)) {
          tags.add(name);
        }
      }
    }

    return {
      for (final tag in tags)
        if (tag.trim().isNotEmpty) tag,
    }.toList();
  }

  static String _subtitleFor(
    String type,
    String format,
    dynamic totalUnits,
    dynamic progress,
  ) {
    final unit = type == 'MANGA' ? 'chapters' : 'episodes';
    final pieces = <String>[
      format.replaceAll('_', ' '),
      if (totalUnits is int && totalUnits > 0) '$totalUnits $unit',
      if (progress is int && progress > 0) '$progress seen',
    ];
    return pieces.join(' · ');
  }

  static List<String> _namesFromNodes(
    dynamic nodes, {
    bool nestedName = false,
  }) {
    if (nodes is! List) return const [];

    return {
      for (final node in nodes)
        if (node is Map) _nameFromNode(node, nestedName: nestedName),
    }.whereType<String>().toList();
  }

  static String? _nameFromNode(
    Map<dynamic, dynamic> node, {
    required bool nestedName,
  }) {
    final value = nestedName ? node['name'] : node;
    if (value is Map) {
      return value['userPreferred']?.toString() ??
          value['full']?.toString() ??
          value['native']?.toString() ??
          value['name']?.toString();
    }
    return node['name']?.toString();
  }

  static const _userCollectionQuery = r'''
    query ($userName: String, $type: MediaType) {
      MediaListCollection(userName: $userName, type: $type) {
        lists {
          entries {
            score(format: POINT_100)
            status
            progress
            updatedAt
            media {
              id
              type
              format
              title { userPreferred romaji english }
              coverImage { extraLarge large }
              genres
              tags { name rank isMediaSpoiler isAdult }
              siteUrl
              characters(page: 1, perPage: 8) {
                nodes { name { userPreferred full native } }
              }
              studios(isMain: true) {
                nodes { name }
              }
              averageScore
              popularity
              episodes
              chapters
              status
              seasonYear
              startDate { year month day }
              description(asHtml: false)
            }
          }
        }
      }
    }
  ''';

  static const _candidateQuery = r'''
    query ($type: MediaType, $page: Int, $perPage: Int, $isAdult: Boolean) {
      Page(page: $page, perPage: $perPage) {
        media(
          type: $type,
          sort: [TRENDING_DESC, POPULARITY_DESC],
          isAdult: $isAdult
        ) {
          id
          type
          format
          title { userPreferred romaji english }
          coverImage { extraLarge large }
          genres
          tags { name rank isMediaSpoiler isAdult }
          siteUrl
          characters(page: 1, perPage: 8) {
            nodes { name { userPreferred full native } }
          }
          studios(isMain: true) {
            nodes { name }
          }
          averageScore
          popularity
          episodes
          chapters
          status
          isAdult
          seasonYear
          startDate { year month day }
          description(asHtml: false)
        }
      }
    }
  ''';

  static const _searchQuery = r'''
    query (
      $type: MediaType,
      $page: Int,
      $perPage: Int,
      $isAdult: Boolean,
      $search: String,
      $formatIn: [MediaFormat],
      $genreIn: [String],
      $tagIn: [String]
    ) {
      Page(page: $page, perPage: $perPage) {
        media(
          type: $type,
          search: $search,
          format_in: $formatIn,
          genre_in: $genreIn,
          tag_in: $tagIn,
          sort: [SEARCH_MATCH, TRENDING_DESC, POPULARITY_DESC],
          isAdult: $isAdult
        ) {
          id
          type
          format
          title { userPreferred romaji english }
          coverImage { extraLarge large }
          genres
          tags { name rank isMediaSpoiler isAdult }
          siteUrl
          characters(page: 1, perPage: 8) {
            nodes { name { userPreferred full native } }
          }
          studios(isMain: true) {
            nodes { name }
          }
          averageScore
          popularity
          episodes
          chapters
          status
          isAdult
          seasonYear
          startDate { year month day }
          description(asHtml: false)
        }
      }
    }
  ''';

  static const _tagsQuery = r'''
    query {
      GenreCollection
      MediaTagCollection {
        name
        isAdult
      }
    }
  ''';

  static const _tasteSignalsQuery = r'''
    query ($userName: String) {
      User(name: $userName) {
        favourites {
          characters(page: 1, perPage: 25) {
            nodes { name { userPreferred full native } }
          }
          staff(page: 1, perPage: 20) {
            nodes { name { userPreferred full native } }
          }
          studios(page: 1, perPage: 20) {
            nodes { name }
          }
        }
      }
    }
  ''';

  static const _knownAniListGenres = {
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Horror',
    'Mahou Shoujo',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
  };
}

class AniListException implements Exception {
  final String message;

  const AniListException(this.message);

  @override
  String toString() => message;
}
