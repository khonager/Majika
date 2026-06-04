import 'package:majika/core/models/media_item.dart';

class RecommendationQuery {
  static const aniListMediaTypes = ['ANIME', 'MANGA'];
  static const steamMediaTypes = ['GAME'];
  static const allMediaTypes = [...aniListMediaTypes, ...steamMediaTypes];

  static const aniListFormats = [
    'TV',
    'TV_SHORT',
    'MOVIE',
    'SPECIAL',
    'OVA',
    'ONA',
    'MUSIC',
    'MANGA',
    'NOVEL',
    'ONE_SHOT',
  ];

  static const steamFormats = [
    'SINGLE_PLAYER',
    'MULTIPLAYER',
    'CO_OP',
    'ONLINE_CO_OP',
    'CONTROLLER',
    'STEAM_DECK',
  ];

  static const allFormats = [...aniListFormats, ...steamFormats];

  static const aniListBrowsableTags = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Horror',
    'Magic',
    'Mahou Shoujo',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
    "Boys' Love",
    'LGBTQ+ Themes',
    'Yuri',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
    'Time Manipulation',
    'Time Skip',
    'Yandere',
    'Stalker',
    'Unrequited Love',
    'Obsession',
    'Tragedy',
    'Urban Fantasy',
    'Coming of Age',
    'Found Family',
    'Anti-Hero',
    'Villainess',
    'Revenge',
    'Survival',
    'Isekai',
    'Cyberpunk',
    'Space',
    'Demons',
    'Vampire',
    'Work',
    'School',
    'Hentai',
  ];

  static const steamBrowsableTags = [
    'Action',
    'Adventure',
    'RPG',
    'Indie',
    'Strategy',
    'Simulation',
    'Casual',
    'Puzzle',
    'Platformer',
    'Shooter',
    'Roguelike',
    'Roguelite',
    'Open World',
    'Horror',
    'Comedy',
    'Funny',
    'Survival',
    'Crafting',
    'Sandbox',
    'Building',
    'Base Building',
    'Automation',
    'Factory',
    'Souls-like',
    'Metroidvania',
    'Deckbuilding',
    'Card Game',
    'Turn-Based',
    'Turn-Based Strategy',
    'Tactical',
    'Real-Time Strategy',
    'Grand Strategy',
    'JRPG',
    'CRPG',
    'Action RPG',
    'Hack and Slash',
    'Loot',
    'Dungeon Crawler',
    'Stealth',
    'Immersive Sim',
    'FPS',
    'Third-Person Shooter',
    'Bullet Hell',
    'Fighting',
    'Racing',
    'Sports',
    'Management',
    'City Builder',
    'Colony Sim',
    'Life Sim',
    'Farming Sim',
    'Dating Sim',
    'Visual Novel',
    'Point & Click',
    'Story Rich',
    'Choices Matter',
    'Exploration',
    'Walking Simulator',
    'Atmospheric',
    'Relaxing',
    'Cozy',
    'Cute',
    'Anime',
    'Pixel Graphics',
    'Retro',
    '2D',
    '3D',
    'VR',
    'Local Multiplayer',
    'Local Co-Op',
    'Split Screen',
    'PvP',
    'PvE',
    'MMO',
    'Massively Multiplayer',
    'Early Access',
    'Free to Play',
    'Single-player',
    'Multiplayer',
    'Co-op',
    'Online Co-op',
    'Controller Support',
    'Steam Deck',
  ];

  static const browsableTags = [...aniListBrowsableTags, ...steamBrowsableTags];

  final String request;
  final Set<String> selectedTags;
  final Set<String> aiSelectedTags;
  final Set<String> mediaTypes;
  final Set<String> formats;
  final bool includeAdult;

  const RecommendationQuery({
    this.request = '',
    this.selectedTags = const {},
    this.aiSelectedTags = const {},
    this.mediaTypes = const {},
    this.formats = const {},
    this.includeAdult = false,
  });

  factory RecommendationQuery.fromJson(Map<String, dynamic> json) {
    return RecommendationQuery(
      request: json['request'] as String? ?? '',
      selectedTags: _jsonStringSet(json['selectedTags']),
      aiSelectedTags: _jsonStringSet(json['aiSelectedTags']),
      mediaTypes: _jsonStringSet(json['mediaTypes']),
      formats: _jsonStringSet(json['formats']),
      includeAdult: json['includeAdult'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'request': request,
      'selectedTags': selectedTags.toList(),
      'aiSelectedTags': aiSelectedTags.toList(),
      'mediaTypes': mediaTypes.toList(),
      'formats': formats.toList(),
      'includeAdult': includeAdult,
    };
  }

  bool get isActive =>
      request.trim().isNotEmpty ||
      selectedTags.isNotEmpty ||
      aiSelectedTags.isNotEmpty ||
      mediaTypes.isNotEmpty ||
      formats.isNotEmpty ||
      includeAdult;

  bool get infersAdult {
    final text = _normalize(request);
    return _containsAny(text, [
      'adult',
      'nsfw',
      'hentai',
      'ecchi',
      'explicit',
      '18+',
    ]);
  }

  bool get infersLocalCoOp {
    final text = _normalize(request);
    return _containsAny(text, [
      'couch co op',
      'couch co-op',
      'local co op',
      'local co-op',
      'local coop',
      'local multiplayer',
      'same pc',
      'same computer',
      'one pc',
      'one computer',
      'two players',
      '2 players',
      'split screen',
      'splitscreen',
      'shared screen',
      'shared/split screen',
    ]);
  }

  bool get infersInfamousLike => _infersInfamousLike(_normalize(request));

  RecommendationQuery copyWith({
    String? request,
    Set<String>? selectedTags,
    Set<String>? aiSelectedTags,
    Set<String>? mediaTypes,
    Set<String>? formats,
    bool? includeAdult,
  }) {
    return RecommendationQuery(
      request: request ?? this.request,
      selectedTags: selectedTags ?? this.selectedTags,
      aiSelectedTags: aiSelectedTags ?? this.aiSelectedTags,
      mediaTypes: mediaTypes ?? this.mediaTypes,
      formats: formats ?? this.formats,
      includeAdult: includeAdult ?? this.includeAdult,
    );
  }

  RecommendationQuery withInferredSelections(Iterable<String> availableTags) {
    return copyWith(
      aiSelectedTags: inferredTags(availableTags),
      mediaTypes: effectiveMediaTypes(),
      formats: effectiveFormats(),
      includeAdult: includeAdult || infersAdult,
    );
  }

  Set<String> effectiveTags(Iterable<String> availableTags) {
    return {...selectedTags, ...aiSelectedTags, ...inferredTags(availableTags)};
  }

  Set<String> specificRequestedTags(Iterable<String> availableTags) {
    final tags = effectiveTags(availableTags);
    return {
      for (final tag in tags)
        if (!_broadRequestTags.contains(tag)) tag,
    };
  }

  Set<String> effectiveFormats() {
    return {...inferredFormats(), ...formats};
  }

  Set<String> effectiveMediaTypes() {
    return mediaTypes.isNotEmpty ? mediaTypes : inferredMediaTypes();
  }

  Set<String> inferredTags(Iterable<String> availableTags) {
    final normalizedRequest = _normalize(request);
    if (normalizedRequest.isEmpty) return {};

    final searchSpace = {...browsableTags, ...availableTags};
    final inferred = <String>{
      for (final tag in searchSpace)
        if (_shouldInferTagFromRequest(normalizedRequest, tag)) tag,
    };

    for (final entry in _fallbackTagHints.entries) {
      if (_containsAny(normalizedRequest, entry.value)) {
        inferred.add(entry.key);
      }
    }

    if (inferred.contains("Boys' Love") || inferred.contains('Yuri')) {
      inferred.remove('LGBTQ+ Themes');
    }

    return inferred;
  }

  Set<String> inferredFormats() {
    final text = _normalize(request);
    final formats = <String>{};

    if (_containsAny(text, ['tv', 'series', 'show', 'anime series'])) {
      formats.add('TV');
    }
    if (_containsAny(text, ['short', 'short anime', 'tv short'])) {
      formats.add('TV_SHORT');
    }
    if (_containsAny(text, ['movie', 'movies', 'film', 'films', 'cinematic'])) {
      formats.add('MOVIE');
    }
    if (_containsAny(text, ['special', 'specials'])) {
      formats.add('SPECIAL');
    }
    if (_containsAny(text, ['ova', 'ovas'])) {
      formats.add('OVA');
    }
    if (_containsAny(text, ['ona', 'onas', 'web anime'])) {
      formats.add('ONA');
    }
    if (_containsAny(text, ['music video', 'music'])) {
      formats.add('MUSIC');
    }
    if (_containsAny(text, ['manga', 'comic', 'comics'])) {
      formats.add('MANGA');
    }
    if (_containsAny(text, [
      'novel',
      'novels',
      'light novel',
      'light novels',
      'ln',
    ])) {
      formats.add('NOVEL');
    }
    if (_containsAny(text, ['one shot', 'oneshot', 'one-shot'])) {
      formats.add('ONE_SHOT');
    }
    if (_containsAny(text, ['single player', 'single-player', 'solo'])) {
      formats.add('SINGLE_PLAYER');
    }
    if (_infersInfamousLike(text)) {
      formats.add('SINGLE_PLAYER');
    }
    if (_containsAny(text, ['multiplayer', 'pvp'])) {
      formats.add('MULTIPLAYER');
    }
    if (_containsAny(text, [
      'co op',
      'co-op',
      'coop',
      'couch co op',
      'couch co-op',
      'local co op',
      'local co-op',
      'local coop',
      'local multiplayer',
      'remote play together',
      'same pc',
      'same computer',
      'one pc',
      'one computer',
      'two players',
      '2 players',
      'split screen',
      'splitscreen',
      'shared screen',
    ])) {
      formats.add('CO_OP');
    }
    if (_containsAny(text, ['online co op', 'online co-op', 'online coop'])) {
      formats.add('ONLINE_CO_OP');
    }
    if (_containsAny(text, [
      'controller',
      'controllers',
      'gamepad',
      'gamepads',
    ])) {
      formats.add('CONTROLLER');
    }
    if (_containsAny(text, ['steam deck', 'deck verified'])) {
      formats.add('STEAM_DECK');
    }

    return formats;
  }

  Set<String> inferredMediaTypes() {
    final text = _normalize(request);
    final types = <String>{};

    if (_containsAny(text, [
      'anime',
      'tv',
      'movie',
      'movies',
      'film',
      'films',
      'special',
      'specials',
      'ova',
      'ovas',
      'ona',
      'onas',
      'music video',
    ])) {
      types.add('ANIME');
    }
    if (_containsAny(text, [
      'manga',
      'comic',
      'comics',
      'novel',
      'novels',
      'light novel',
      'light novels',
      'ln',
    ])) {
      types.add('MANGA');
    }
    if (_containsAny(text, [
      'computer',
      'game',
      'games',
      'pc',
      'steam',
      'play',
      'roguelike',
    ])) {
      types.add('GAME');
    }
    if (_infersInfamousLike(text)) {
      types.add('GAME');
    }

    return types;
  }

  String get aniListSearchText => _searchTerms().take(5).join(' ');

  bool matchesText(MediaItem item) {
    if (effectiveTags(item.tags).isNotEmpty || effectiveFormats().isNotEmpty) {
      return true;
    }

    final terms = _searchTerms();
    if (terms.isEmpty) return true;

    final haystack = _normalize(
      [
        item.title,
        item.subtitle,
        item.format,
        item.mediaType,
        item.description ?? '',
        ...item.tags,
      ].join(' '),
    );

    return terms.any(haystack.contains);
  }

  List<String> _searchTerms() {
    const stopWords = {
      'a',
      'about',
      'an',
      'and',
      'for',
      'find',
      'give',
      'i',
      'in',
      'me',
      'of',
      'or',
      'recommend',
      'recommendations',
      'show',
      'something',
      'that',
      'the',
      'to',
      'want',
      'with',
    };

    const structuralTerms = {
      'adult',
      'anime',
      'cinematic',
      'comic',
      'ecchi',
      'explicit',
      'film',
      'hentai',
      'light',
      'manga',
      'movie',
      'novel',
      'nsfw',
      'ona',
      'ova',
      'game',
      'games',
      'play',
      'steam',
      'series',
      'show',
      'special',
      'tv',
    };

    return _normalize(request)
        .split(RegExp(r'[^a-z0-9+]+'))
        .where(
          (term) =>
              term.length > 2 &&
              !stopWords.contains(term) &&
              !structuralTerms.contains(term),
        )
        .toList();
  }

  static bool _containsAny(String text, Iterable<String> values) {
    return values.any((value) => _containsWholePhrase(text, _normalize(value)));
  }

  static bool _shouldInferTagFromRequest(String normalizedRequest, String tag) {
    final normalizedTag = _normalize(tag);
    if (normalizedTag.isEmpty || _blockedAutoTags.contains(normalizedTag)) {
      return false;
    }
    return _containsWholePhrase(normalizedRequest, normalizedTag);
  }

  static bool _containsWholePhrase(String text, String phrase) {
    final escaped = RegExp.escape(phrase);
    return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(text);
  }

  static bool _infersInfamousLike(String text) {
    return _containsAny(text, [
      'infamous game',
      'infamous games',
      'in famous game',
      'in famous games',
      'infamous-like',
      'infamous like',
      'in famous-like',
      'in famous like',
    ]);
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  static const Set<String> _blockedAutoTags = {
    // AniList's Kids tag is a demographic/content bucket. A request like
    // "good to watch with kids" is better handled as family-friendly intent,
    // not as a hard Kids tag filter.
    'kids',
  };

  static const Set<String> _broadRequestTags = {
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Horror',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
    'RPG',
    'Indie',
    'Strategy',
    'Simulation',
    'Casual',
    'Puzzle',
    'Platformer',
    'Shooter',
    'Roguelike',
    'Open World',
    'School',
    'Work',
  };

  static Set<String> _jsonStringSet(Object? value) {
    if (value is! List) return {};
    return {
      for (final item in value)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    };
  }

  static const Map<String, List<String>> _fallbackTagHints = {
    'Romance': ['romance', 'romantic', 'love story', 'relationship'],
    "Boys' Love": [
      'boys love',
      "boy's love",
      "boys' love",
      'bl anime',
      'bl manga',
      'yaoi',
      'shounen ai',
      'shonen ai',
      'male male romance',
      'male/male romance',
      'male x male',
      'm/m romance',
      'mlm romance',
      'gay romance',
      'homosexual romance',
      'romance between two males',
      'romance between two boys',
      'two males in love',
      'two boys in love',
      'between two males',
      'between two boys',
    ],
    'LGBTQ+ Themes': [
      'lgbt',
      'lgbtq',
      'lgbtq+',
      'queer',
      'gay',
      'lesbian',
      'homosexual',
      'same sex',
      'same-sex',
      'mlm',
      'wlw',
    ],
    'Yuri': [
      'yuri',
      'girls love',
      "girl's love",
      "girls' love",
      'shoujo ai',
      'shojo ai',
      'female female romance',
      'female/female romance',
      'female x female',
      'f/f romance',
      'wlw romance',
      'lesbian romance',
      'romance between two females',
      'romance between two girls',
      'two females in love',
      'two girls in love',
    ],
    'Time Manipulation': [
      'time travel',
      'time loop',
      'time traveller',
      'time traveler',
      'rewind time',
      'back in time',
    ],
    'Yandere': [
      'obsessed character',
      'obsessive character',
      'obsessive love',
      'possessive love',
      'dangerously in love',
      'crazy girlfriend',
      'crazy boyfriend',
    ],
    'Stalker': ['stalker', 'stalking'],
    'Psychological': ['mind game', 'mind games', 'psychological'],
    'Thriller': ['thriller', 'suspense', 'tense'],
    'Mystery': ['mystery', 'detective', 'whodunit', 'investigation'],
    'Sci-Fi': ['science fiction', 'sci fi', 'sci-fi', 'future tech'],
    'Slice of Life': ['slice of life', 'cozy', 'chill'],
    'Horror': ['horror', 'scary', 'creepy'],
    'Comedy': [
      'entertaining',
      'funny',
      'comedy',
      'comedic',
      'laugh',
      'laughing',
      'laugh a lot',
      'spy family',
      'spy x family',
    ],
    'Family Life': [
      'family anime',
      'family friendly',
      'family-friendly',
      'watch with kids',
      'watch with parents',
      'kids and parents',
      'parents and kids',
      'spy family',
      'spy x family',
    ],
    'Hentai': ['hentai', 'explicit adult'],
    'Ecchi': ['ecchi', 'fanservice'],
    'Action': [
      'action',
      'fight',
      'fighting',
      'infamous game',
      'infamous games',
    ],
    'Adventure': [
      'adventure',
      'exploration',
      'explore',
      'infamous game',
      'infamous games',
    ],
    'Fantasy': ['fantasy', 'harry potter', 'wizard', 'witch', 'witchcraft'],
    'RPG': ['role playing', 'role-playing', 'rpg'],
    'Strategy': ['strategy', 'tactics', 'tactical'],
    'Simulation': ['simulation', 'simulator', 'management'],
    'Puzzle': ['puzzle', 'brain teaser'],
    'Shooter': ['shooter', 'fps', 'third person shooter'],
    'Roguelike': ['roguelike', 'roguelite', 'run based'],
    'Open World': ['open world', 'sandbox', 'infamous game', 'infamous games'],
    'Supernatural': ['super powers', 'superpowers', 'infamous games'],
    'Co-op': ['co op', 'co-op', 'coop'],
    'Multiplayer': ['multiplayer', 'pvp'],
    'Magic': [
      'magic',
      'magical',
      'mage',
      'wizard',
      'witch',
      'spell',
      'spells',
      'sorcery',
      'harry potter',
      'hogwarts',
      'mashle',
    ],
    'School': [
      'school',
      'academy',
      'magic school',
      'wizard school',
      'hogwarts',
      'harry potter',
      'mashle',
      'wistoria',
    ],
    'Coming of Age': ['coming of age', 'harry potter'],
  };
}
