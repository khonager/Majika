import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/user_taste_signals.dart';
import 'package:majika/core/services/media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SteamApiKeyProvider = Future<String?> Function();

abstract class SteamProtectedApi {
  Future<Map<String, dynamic>> resolveVanityUrl(String vanity);

  Future<Map<String, dynamic>> getPlayerSummaries(String steamId);

  Future<Map<String, dynamic>> getOwnedGames(String steamId);

  Future<Map<String, dynamic>> getRecentlyPlayedGames(String steamId);
}

class SteamService implements MediaService {
  SteamService({
    http.Client? client,
    SteamApiKeyProvider? apiKeyProvider,
    SteamProtectedApi? protectedApi,
  }) : _client = client ?? http.Client(),
       _apiKeyProvider = apiKeyProvider ?? _savedApiKey,
       _protectedApi = protectedApi;

  static const sourceId = 'com.majika.service.steam';
  static const _steamApi = 'https://api.steampowered.com';
  static const _storeApi = 'https://store.steampowered.com/api';

  static const _candidateAppIds = [
    730, // Counter-Strike 2
    570, // Dota 2
    1172470, // Apex Legends
    1086940, // Baldur's Gate 3
    1245620, // Elden Ring
    292030, // The Witcher 3
    1091500, // Cyberpunk 2077
    413150, // Stardew Valley
    646570, // Slay the Spire
    367520, // Hollow Knight
    1145360, // Hades
    1623730, // Palworld
    271590, // GTA V Legacy
    1938090, // Call of Duty
    252490, // Rust
    440, // Team Fortress 2
    578080, // PUBG
    105600, // Terraria
    1222670, // The Sims 4
    381210, // Dead by Daylight
    594650, // Hunt: Showdown
    250900, // Binding of Isaac: Rebirth
    221100, // DayZ
    359550, // Rainbow Six Siege
  ];
  static const _adultCandidateAppIds = [
    339800, // HuniePop
    930210, // HuniePop 2: Double Date
    1126320, // Being a DIK - Season 1
    611790, // House Party
    644560, // Mirror
    407330, // Sakura Dungeon
    459820, // Crush Crush
    1034140, // Subverse
    939400, // LoveChoice
    765870, // Leisure Suit Larry - Wet Dreams Don't Dry
    402180, // Sakura Swim Club
  ];

  final http.Client _client;
  final SteamApiKeyProvider _apiKeyProvider;
  final SteamProtectedApi? _protectedApi;

  @override
  String get id => sourceId;

  @override
  String get displayName => 'Steam';

  @override
  String get connectTitle => 'Connect Steam';

  @override
  String get connectDescription =>
      'Enter a public Steam profile URL, SteamID64, or vanity name. Majika will read public games, infer favorite and most-played signals, then recommend games from current Steam data.';

  @override
  String get userNameHint => 'Steam profile, vanity name, or SteamID64';

  @override
  String get userNameEmptyMessage => 'Enter a Steam profile first.';

  @override
  String get importButtonLabel => 'Build game profile';

  @override
  String get searchPlaceholder => 'Search a genre, mode, game, or vibe';

  @override
  String get openTooltipLabel => 'Open on Steam';

  @override
  List<String> get supportedMediaTypes => RecommendationQuery.steamMediaTypes;

  @override
  List<String> get supportedFormats => RecommendationQuery.steamFormats;

  @override
  bool get supportsAdultContent => true;

  @override
  Future<ServiceUserProfile?> fetchUserProfile(String userName) async {
    final steamId = await resolveSteamId(userName);
    final decoded = await _protectedSteamApi().getPlayerSummaries(steamId);
    return parseUserProfile(decoded, fallbackUserName: userName);
  }

  @override
  Future<List<MediaItem>> fetchUserLibrary(String userName) async {
    final steamId = await resolveSteamId(userName);
    final steamApi = _protectedSteamApi();
    final owned = parseOwnedGames(await steamApi.getOwnedGames(steamId));
    final recent = parseRecentGames(
      await steamApi.getRecentlyPlayedGames(steamId),
    );
    final merged = _mergeRecentPlay(owned, recent);
    if (merged.isEmpty) return merged;

    final topGames = [...merged]
      ..sort(
        (a, b) => (b.playtimeMinutes ?? 0).compareTo(a.playtimeMinutes ?? 0),
      );
    final enrichableIds = topGames.take(80).map(_steamAppId).whereType<int>();
    final details = await _fetchAppDetails(enrichableIds);
    return [
      for (final item in merged)
        _mergeDetails(item, details[_steamAppId(item)]),
    ];
  }

  @override
  Future<UserTasteSignals> fetchTasteSignals(String userName) async {
    final _ = userName;
    return UserTasteSignals.empty;
  }

  @override
  Future<List<MediaItem>> fetchRecommendationCandidates({
    bool includeAdult = false,
  }) async {
    final appIds = includeAdult
        ? [..._candidateAppIds, ..._adultCandidateAppIds]
        : _candidateAppIds;
    final details = await _fetchAppDetails(appIds);
    return details.values.toList();
  }

  @override
  Future<List<MediaItem>> searchRecommendationCandidates(
    RecommendationQuery query,
  ) async {
    final terms = _storeSearchTermsForQuery(query);
    final termResults = await Future.wait([
      for (final term in terms) _storeSearchAppIds(term),
    ]);
    final appIds = <int>{
      for (final result in termResults) ...result.take(8),
    }.toList();
    final items = appIds.isEmpty
        ? <MediaItem>[]
        : (await _fetchAppDetails(appIds)).values.toList();

    if (_shouldAppendBaselineCandidates(query, items)) {
      final baseline = await fetchRecommendationCandidates();
      return _dedupe([...items, ...baseline]);
    }

    return _dedupe(items);
  }

  static bool _shouldAppendBaselineCandidates(
    RecommendationQuery query,
    List<MediaItem> items,
  ) {
    final searchText = query.searchRequest.trim();
    if (searchText.isEmpty) return true;
    final terms = query.aniListSearchText
        .split(' ')
        .where((term) => term.trim().isNotEmpty)
        .toList();
    if (terms.length >= 2) return false;
    return items.isEmpty;
  }

  Future<List<int>> _storeSearchAppIds(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.parse('$_storeApi/storesearch/').replace(
      queryParameters: {
        'term': trimmed,
        'l': 'en',
        'cc': 'us',
        'category1': '998',
      },
    );
    final decoded = await _getJson(uri);
    return parseStoreSearchAppIds(decoded);
  }

  static List<String> _storeSearchTermsForQuery(RecommendationQuery query) {
    final terms = <String>[];
    final seen = <String>{};

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) return;
      terms.add(trimmed);
    }

    final text = query.searchRequest.trim();
    final hasSpecificText =
        query.aniListSearchText
            .split(' ')
            .where((term) => term.trim().isNotEmpty)
            .length >=
        2;
    for (final term in expandedSteamStoreSearchTerms(text)) {
      add(term);
    }

    for (final tag in {...query.selectedTags, ...query.aiSelectedTags}) {
      add(tag);
      if (text.isNotEmpty) add('$text $tag');
    }

    for (final format in query.effectiveFormats()) {
      if (hasSpecificText &&
          (format == 'CONTROLLER' || format == 'STEAM_DECK')) {
        continue;
      }
      final label = _steamFormatSearchLabel(format);
      if (label.isEmpty) continue;
      add(label);
      if (text.isNotEmpty) add('$text $label');
    }

    return terms;
  }

  static List<String> expandedSteamStoreSearchTerms(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return const [];

    final variants = <String>[];

    void add(String value) {
      final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (normalized.isEmpty) return;
      if (variants.contains(normalized)) return;
      variants.add(normalized);
    }

    add(trimmed);

    var simplified = trimmed.toLowerCase();
    for (final prefix in const [
      'i want to pretend to be ',
      'i want to be ',
      'i want to ',
      'want to pretend to be ',
      'want to be ',
      'want to ',
      'i am looking for ',
      'i m looking for ',
      'im looking for ',
      'looking for ',
      'pretend to be ',
      'pretend i am ',
      'pretend i m ',
      'pretend im ',
      'a game about ',
      'game about ',
      'a game where you ',
      'game where you ',
      'a game with ',
      'game with ',
      'a game ',
      'game ',
    ]) {
      if (simplified.startsWith(prefix)) {
        add(trimmed.substring(prefix.length));
        simplified = trimmed.substring(prefix.length).toLowerCase();
        break;
      }
    }

    final keywords = simplified
        .split(RegExp(r'[^a-z0-9]+'))
        .where(
          (term) =>
              term.isNotEmpty &&
              !_steamSearchStopWords.contains(term) &&
              !_steamSearchGenericTerms.contains(term),
        )
        .toList();

    if (keywords.isNotEmpty) {
      add(keywords.join(' '));
    }
    for (var i = 0; i <= keywords.length - 2; i++) {
      add(keywords.sublist(i, i + 2).join(' '));
    }
    for (var i = 0; i <= keywords.length - 3; i++) {
      add(keywords.sublist(i, i + 3).join(' '));
    }
    if (keywords.length >= 2) {
      add(keywords.sublist(keywords.length - 2).join(' '));
    }
    if (keywords.length >= 3) {
      add(keywords.sublist(keywords.length - 3).join(' '));
    }

    final lastKeyword = keywords.isNotEmpty ? keywords.last : '';
    final lastTwoKeywords = keywords.length >= 2
        ? keywords.sublist(keywords.length - 2).join(' ')
        : lastKeyword;
    if (lastTwoKeywords.isNotEmpty) {
      add('$lastTwoKeywords simulator');
    }
    if (lastKeyword.isNotEmpty &&
        !_steamSimulatorSuffixBlockedTerms.contains(lastKeyword)) {
      add('$lastKeyword simulator');
    }
    return variants;
  }

  static const _steamSearchStopWords = {
    'a',
    'about',
    'an',
    'and',
    'big',
    'for',
    'get',
    'gets',
    'i',
    'just',
    'kind',
    'in',
    'like',
    'looking',
    'me',
    'of',
    'on',
    'pretend',
    'really',
    'sort',
    'that',
    'the',
    'to',
    'want',
    'where',
    'with',
    'you',
  };

  static const _steamSearchGenericTerms = {
    'game',
    'games',
    'operating',
    'play',
    'playing',
  };

  static const _steamSimulatorSuffixBlockedTerms = {
    'simulator',
    'simulation',
    'sim',
  };

  static String _steamFormatSearchLabel(String format) {
    return switch (format) {
      'SINGLE_PLAYER' => 'single-player',
      'MULTIPLAYER' => 'multiplayer',
      'CO_OP' => 'co-op',
      'ONLINE_CO_OP' => 'online co-op',
      'CONTROLLER' => 'controller support',
      'STEAM_DECK' => 'steam deck',
      _ => '',
    };
  }

  @override
  Future<List<String>> fetchAvailableTags() async {
    return RecommendationQuery.steamBrowsableTags;
  }

  Future<String> resolveSteamId(String input) async {
    final trimmed = input.trim();
    final directId = _steamIdFromInput(trimmed);
    if (directId != null) return directId;

    final vanity = _vanityFromInput(trimmed);
    if (vanity == null || vanity.isEmpty) {
      throw const SteamException(
        'Enter a SteamID64, vanity name, or profile URL.',
      );
    }

    return parseResolveVanity(
      await _protectedSteamApi().resolveVanityUrl(vanity),
    );
  }

  SteamProtectedApi _protectedSteamApi() {
    return _protectedApi ?? _DirectSteamProtectedApi(this);
  }

  Future<Map<int, MediaItem>> _fetchAppDetails(Iterable<int> appIds) async {
    final details = <int, MediaItem>{};
    for (final appId in appIds.toSet()) {
      final uri = Uri.parse('$_storeApi/appdetails').replace(
        queryParameters: {
          'appids': '$appId',
          'l': 'en',
          'cc': 'us',
          'filters':
              'basic,genres,categories,content_descriptors,release_date,metacritic',
        },
      );
      try {
        final decoded = await _getJson(uri);
        final item = parseAppDetails(decoded, appId: appId);
        if (item != null) details[appId] = item;
      } catch (_) {
        // Store app details can be missing for delisted apps; keep the import moving.
      }
    }
    return details;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client
        .get(uri, headers: const {'User-Agent': 'Majika/1.0'})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SteamException('Steam returned HTTP ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Steam response was not a JSON object.');
  }

  Future<String> _requiredApiKey() async {
    final key = (await _apiKeyProvider())?.trim();
    if (key == null || key.isEmpty) {
      throw const SteamException(
        'Add a Steam Web API key in Settings before importing Steam.',
      );
    }
    return key;
  }

  static Future<String?> _savedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(LocalAiSettingsKeys.steamApiKey);
  }

  static String parseResolveVanity(Map<String, dynamic> json) {
    final response = json['response'];
    if (response is! Map) {
      throw const SteamException('Steam vanity lookup returned no response.');
    }
    if (response['success'] == 1 && response['steamid'] != null) {
      return response['steamid'].toString();
    }
    final message = response['message']?.toString();
    throw SteamException(
      message == null || message.isEmpty
          ? 'Could not resolve that Steam profile.'
          : message,
    );
  }

  static ServiceUserProfile? parseUserProfile(
    Map<String, dynamic> json, {
    required String fallbackUserName,
  }) {
    final players = json['response']?['players'];
    if (players is! List || players.isEmpty) return null;
    final player = players.first;
    if (player is! Map) return null;
    final steamId = player['steamid']?.toString() ?? fallbackUserName;
    return ServiceUserProfile(
      userName: steamId,
      displayName: player['personaname']?.toString() ?? fallbackUserName,
      avatarUrl:
          player['avatarfull']?.toString() ??
          player['avatarmedium']?.toString() ??
          '',
      profileUrl:
          player['profileurl']?.toString() ??
          'https://steamcommunity.com/profiles/$steamId',
    );
  }

  static List<MediaItem> parseOwnedGames(Map<String, dynamic> json) {
    final games = json['response']?['games'];
    if (games is! List) return const [];
    return _dedupe([
      for (final game in games)
        if (game is Map) _mediaFromOwnedGame(game),
    ]);
  }

  static List<MediaItem> parseRecentGames(Map<String, dynamic> json) {
    final games = json['response']?['games'];
    if (games is! List) return const [];
    return _dedupe([
      for (final game in games)
        if (game is Map) _mediaFromOwnedGame(game, recentlyPlayed: true),
    ]);
  }

  static List<int> parseStoreSearchAppIds(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map && item['id'] is num) (item['id'] as num).toInt(),
    ];
  }

  static MediaItem? parseAppDetails(
    Map<String, dynamic> json, {
    required int appId,
  }) {
    final wrapper = json['$appId'];
    if (wrapper is! Map || wrapper['success'] != true) return null;
    final data = wrapper['data'];
    if (data is! Map) return null;
    final type = data['type']?.toString().trim().toLowerCase() ?? '';
    if (type.isNotEmpty && type != 'game') return null;
    return _mediaFromAppDetails(appId, data);
  }

  static MediaItem _mediaFromOwnedGame(
    Map<dynamic, dynamic> game, {
    bool recentlyPlayed = false,
  }) {
    final appId = (game['appid'] as num?)?.toInt() ?? 0;
    final playtime = (game['playtime_forever'] as num?)?.toInt();
    final recentPlaytime = (game['playtime_2weeks'] as num?)?.toInt();
    final lastPlayed = (game['rtime_last_played'] as num?)?.toInt();
    return MediaItem(
      id: 'steam_$appId',
      title: game['name']?.toString() ?? 'Steam App $appId',
      coverUrl: appId > 0
          ? 'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg'
          : '',
      tags: const [],
      rating: _playtimeRating(playtime),
      subtitle: _playtimeSubtitle(playtime, recentPlaytime),
      extensionId: sourceId,
      sourceId: sourceId,
      mediaType: 'GAME',
      format: 'GAME',
      status: recentlyPlayed || (recentPlaytime ?? 0) > 0
          ? 'RECENTLY_PLAYED'
          : 'OWNED',
      siteUrl: 'https://store.steampowered.com/app/$appId',
      updatedAt: lastPlayed,
      playtimeMinutes: playtime,
      recentPlaytimeMinutes: recentPlaytime,
      lastPlayedAt: lastPlayed,
    );
  }

  static MediaItem _mediaFromAppDetails(int appId, Map<dynamic, dynamic> data) {
    final genres = _descriptions(data['genres']);
    final categories = _descriptions(data['categories']);
    final contentNotes = _contentDescriptorNotes(data['content_descriptors']);
    final evidenceText = [
      data['name']?.toString() ?? '',
      data['short_description']?.toString() ?? '',
      contentNotes,
      ...genres,
      ...categories,
    ].join(' ');
    final adultTags = _adultTagsFromEvidence(evidenceText);
    final tags = _normalizeTags([...genres, ...categories, ...adultTags]);
    final metacriticScore = data['metacritic'] is Map
        ? (data['metacritic']['score'] as num?)?.toDouble()
        : null;
    final releaseYear = _releaseYear(data['release_date']);
    final developers = _stringList(data['developers']);
    final publishers = _stringList(data['publishers']);
    return MediaItem(
      id: 'steam_$appId',
      title: data['name']?.toString() ?? 'Steam App $appId',
      coverUrl:
          data['header_image']?.toString() ??
          'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg',
      tags: tags,
      rating: metacriticScore == null ? null : metacriticScore / 10,
      subtitle: _storeSubtitle(tags, releaseYear),
      extensionId: sourceId,
      sourceId: sourceId,
      mediaType: 'GAME',
      format: _formatFromTags(tags),
      description: data['short_description']?.toString(),
      siteUrl: data['steam_appid'] == null
          ? 'https://store.steampowered.com/app/$appId'
          : 'https://store.steampowered.com/app/${data["steam_appid"]}',
      studios: {...developers, ...publishers}.toList(),
      startYear: releaseYear,
      popularity: _syntheticPopularity(data),
      isAdult: adultTags.isNotEmpty,
    );
  }

  static List<MediaItem> _mergeRecentPlay(
    List<MediaItem> owned,
    List<MediaItem> recent,
  ) {
    final byId = {for (final item in owned) item.id: item};
    for (final item in recent) {
      final existing = byId[item.id];
      byId[item.id] = existing == null
          ? item
          : existing.copyWith(
              status: 'RECENTLY_PLAYED',
              recentPlaytimeMinutes: item.recentPlaytimeMinutes,
              lastPlayedAt: item.lastPlayedAt ?? existing.lastPlayedAt,
              updatedAt: item.lastPlayedAt ?? existing.updatedAt,
            );
    }
    return byId.values.toList();
  }

  static MediaItem _mergeDetails(MediaItem libraryItem, MediaItem? details) {
    if (details == null) return libraryItem;
    return details.copyWith(
      rating: details.rating ?? libraryItem.rating,
      status: libraryItem.status,
      subtitle: libraryItem.subtitle,
      playtimeMinutes: libraryItem.playtimeMinutes,
      recentPlaytimeMinutes: libraryItem.recentPlaytimeMinutes,
      lastPlayedAt: libraryItem.lastPlayedAt,
      updatedAt: libraryItem.updatedAt,
    );
  }

  static String? _steamIdFromInput(String input) {
    final profileMatch = RegExp(r'/profiles/(\d{15,20})').firstMatch(input);
    if (profileMatch != null) return profileMatch.group(1);
    if (RegExp(r'^\d{15,20}$').hasMatch(input)) return input;
    return null;
  }

  static String? _vanityFromInput(String input) {
    final match = RegExp(r'/id/([^/?#]+)').firstMatch(input);
    if (match != null) return Uri.decodeComponent(match.group(1)!);
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return null;
    }
    return input;
  }

  static int? _steamAppId(MediaItem item) {
    final match = RegExp(r'^steam_(\d+)$').firstMatch(item.id);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static List<String> _descriptions(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map && item['description'] != null)
          item['description'].toString(),
    ];
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null) item.toString(),
    ];
  }

  static String _contentDescriptorNotes(Object? value) {
    if (value is! Map) return '';
    return value['notes']?.toString() ?? '';
  }

  static List<String> _adultTagsFromEvidence(String value) {
    final text = _normalizeEvidence(value);
    if (!_containsAdultEvidence(text)) return const [];

    final tags = <String>{'Sexual Content', 'Mature', 'NSFW'};
    if (_containsWholePhrase(text, 'hentai')) tags.add('Hentai');
    if (_containsAnyWholePhrase(text, const ['nude', 'nudity', 'naked'])) {
      tags.add('Nudity');
    }
    if (_containsAnyWholePhrase(text, const [
      'dating sim',
      'dating simulator',
    ])) {
      tags.add('Dating Sim');
    }
    if (_containsWholePhrase(text, 'visual novel')) {
      tags.add('Visual Novel');
    }
    return tags.toList();
  }

  static bool _containsAdultEvidence(String text) {
    return _containsAnyWholePhrase(text, const [
      '18+',
      '18 plus',
      'adult visual novel',
      'adult version',
      'adult',
      'eroge',
      'erotic',
      'explicit',
      'hentai',
      'horny',
      'lewd',
      'naughty',
      'nsfw',
      'porn',
      'pornography',
      'r18',
      'sex',
      'sexual',
      'sexual content',
      'sexy',
      'smut',
      'steamy',
      'uncensored',
    ]);
  }

  static bool _containsAnyWholePhrase(String text, Iterable<String> values) {
    return values.any((value) => _containsWholePhrase(text, value));
  }

  static bool _containsWholePhrase(String text, String phrase) {
    final escaped = RegExp.escape(_normalizeEvidence(phrase));
    return RegExp('(^|[^a-z0-9+])$escaped([^a-z0-9+]|\$)').hasMatch(text);
  }

  static String _normalizeEvidence(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  static List<String> _normalizeTags(List<String> values) {
    final mapped = <String>{};
    for (final value in values) {
      final normalized = value.toLowerCase();
      if (normalized.contains('single-player')) mapped.add('Single-player');
      if (normalized.contains('multi-player')) mapped.add('Multiplayer');
      if (normalized.contains('co-op')) mapped.add('Co-op');
      if (normalized.contains('online co-op')) mapped.add('Online Co-op');
      if (normalized.contains('controller')) mapped.add('Controller Support');
      if (normalized.contains('deck')) mapped.add('Steam Deck');
      if (RegExp(r'(^|[^a-z0-9])vr([^a-z0-9]|$)').hasMatch(normalized) ||
          normalized.contains('virtual reality')) {
        mapped.add('VR');
      }
      mapped.add(value.replaceAll(RegExp(r'\s+'), ' ').trim());
    }
    return [
      for (final tag in mapped)
        if (tag.isNotEmpty) tag,
    ];
  }

  static String _formatFromTags(List<String> tags) {
    if (tags.contains('Online Co-op')) return 'ONLINE_CO_OP';
    if (tags.contains('Co-op')) return 'CO_OP';
    if (tags.contains('Multiplayer')) return 'MULTIPLAYER';
    if (tags.contains('Single-player')) return 'SINGLE_PLAYER';
    return 'GAME';
  }

  static String _playtimeSubtitle(int? playtime, int? recentPlaytime) {
    final hours = ((playtime ?? 0) / 60).round();
    final recentHours = ((recentPlaytime ?? 0) / 60).round();
    final parts = <String>[
      if (hours > 0) '$hours hours played' else 'In library',
      if (recentHours > 0) '$recentHours hours recently',
    ];
    return parts.join(' · ');
  }

  static String _storeSubtitle(List<String> tags, int? releaseYear) {
    final pieces = <String>[
      if (releaseYear != null) '$releaseYear',
      ...tags.take(2),
    ];
    return pieces.join(' · ');
  }

  static int? _releaseYear(Object? releaseDate) {
    if (releaseDate is! Map) return null;
    final date = releaseDate['date']?.toString();
    if (date == null) return null;
    final match = RegExp(r'(19|20)\d\d').firstMatch(date);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static int? _syntheticPopularity(Map<dynamic, dynamic> data) {
    final recommendations = data['recommendations'];
    if (recommendations is Map && recommendations['total'] is num) {
      return (recommendations['total'] as num).toInt();
    }
    final score = data['metacritic'] is Map
        ? (data['metacritic']['score'] as num?)?.toInt()
        : null;
    return score == null ? null : max(0, score * 250);
  }

  static double? _playtimeRating(int? minutes) {
    if (minutes == null || minutes <= 0) return null;
    final hours = minutes / 60;
    return min(10, 5.8 + log(hours + 1) / log(10) * 1.8);
  }

  static List<MediaItem> _dedupe(List<MediaItem> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }
}

class _DirectSteamProtectedApi implements SteamProtectedApi {
  final SteamService _service;

  const _DirectSteamProtectedApi(this._service);

  @override
  Future<Map<String, dynamic>> resolveVanityUrl(String vanity) async {
    final key = await _service._requiredApiKey();
    final uri = Uri.parse(
      '${SteamService._steamApi}/ISteamUser/ResolveVanityURL/v1/',
    ).replace(queryParameters: {'key': key, 'vanityurl': vanity});
    return _service._getJson(uri);
  }

  @override
  Future<Map<String, dynamic>> getPlayerSummaries(String steamId) async {
    final key = await _service._requiredApiKey();
    final uri = Uri.parse(
      '${SteamService._steamApi}/ISteamUser/GetPlayerSummaries/v2/',
    ).replace(queryParameters: {'key': key, 'steamids': steamId});
    return _service._getJson(uri);
  }

  @override
  Future<Map<String, dynamic>> getOwnedGames(String steamId) async {
    final key = await _service._requiredApiKey();
    final uri =
        Uri.parse(
          '${SteamService._steamApi}/IPlayerService/GetOwnedGames/v1/',
        ).replace(
          queryParameters: {
            'key': key,
            'steamid': steamId,
            'include_appinfo': 'true',
            'include_played_free_games': 'true',
            'format': 'json',
          },
        );
    return _service._getJson(uri);
  }

  @override
  Future<Map<String, dynamic>> getRecentlyPlayedGames(String steamId) async {
    final key = await _service._requiredApiKey();
    final uri =
        Uri.parse(
          '${SteamService._steamApi}/IPlayerService/GetRecentlyPlayedGames/v1/',
        ).replace(
          queryParameters: {'key': key, 'steamid': steamId, 'format': 'json'},
        );
    return _service._getJson(uri);
  }
}

class SteamException implements Exception {
  final String message;

  const SteamException(this.message);

  @override
  String toString() => message;
}
