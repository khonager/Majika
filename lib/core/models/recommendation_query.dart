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

  static const browsableTags = [
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
    'Single-player',
    'Multiplayer',
    'Co-op',
    'Online Co-op',
    'Controller Support',
    'Steam Deck',
  ];

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

  Set<String> effectiveFormats() {
    return formats.isNotEmpty ? formats : inferredFormats();
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
        if (normalizedRequest.contains(_normalize(tag))) tag,
    };

    for (final entry in _fallbackTagHints.entries) {
      if (_containsAny(normalizedRequest, entry.value)) {
        inferred.add(entry.key);
      }
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
    if (_containsAny(text, ['movie', 'film', 'cinematic'])) {
      formats.add('MOVIE');
    }
    if (_containsAny(text, ['special'])) {
      formats.add('SPECIAL');
    }
    if (_containsAny(text, ['ova'])) {
      formats.add('OVA');
    }
    if (_containsAny(text, ['ona', 'web anime'])) {
      formats.add('ONA');
    }
    if (_containsAny(text, ['music video', 'music'])) {
      formats.add('MUSIC');
    }
    if (_containsAny(text, ['manga', 'comic'])) {
      formats.add('MANGA');
    }
    if (_containsAny(text, ['novel', 'light novel', 'ln'])) {
      formats.add('NOVEL');
    }
    if (_containsAny(text, ['one shot', 'oneshot', 'one-shot'])) {
      formats.add('ONE_SHOT');
    }
    if (_containsAny(text, ['single player', 'single-player', 'solo'])) {
      formats.add('SINGLE_PLAYER');
    }
    if (_containsAny(text, ['multiplayer', 'pvp'])) {
      formats.add('MULTIPLAYER');
    }
    if (_containsAny(text, ['co op', 'co-op', 'coop'])) {
      formats.add('CO_OP');
    }
    if (_containsAny(text, ['online co op', 'online co-op', 'online coop'])) {
      formats.add('ONLINE_CO_OP');
    }
    if (_containsAny(text, ['controller', 'gamepad'])) {
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
      'film',
      'special',
      'ova',
      'ona',
      'music video',
    ])) {
      types.add('ANIME');
    }
    if (_containsAny(text, ['manga', 'comic', 'novel', 'light novel', 'ln'])) {
      types.add('MANGA');
    }
    if (_containsAny(text, ['game', 'games', 'steam', 'play', 'roguelike'])) {
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
    return values.any((value) => text.contains(_normalize(value)));
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  static const Map<String, List<String>> _fallbackTagHints = {
    'Romance': ['romance', 'romantic', 'love story', 'relationship'],
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
    'Comedy': ['funny', 'comedy', 'comedic'],
    'Hentai': ['hentai', 'explicit adult'],
    'Ecchi': ['ecchi', 'fanservice'],
    'Fantasy': ['fantasy', 'harry potter', 'wizard', 'witch', 'witchcraft'],
    'RPG': ['role playing', 'role-playing', 'rpg'],
    'Strategy': ['strategy', 'tactics', 'tactical'],
    'Simulation': ['simulation', 'simulator', 'management'],
    'Puzzle': ['puzzle', 'brain teaser'],
    'Shooter': ['shooter', 'fps', 'third person shooter'],
    'Roguelike': ['roguelike', 'roguelite', 'run based'],
    'Open World': ['open world', 'sandbox'],
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
