import 'package:majika/core/models/media_item.dart';

class RecommendationQuery {
  final String request;
  final Set<String> selectedTags;
  final Set<String> mediaTypes;
  final Set<String> formats;
  final bool includeAdult;

  const RecommendationQuery({
    this.request = '',
    this.selectedTags = const {},
    this.mediaTypes = const {},
    this.formats = const {},
    this.includeAdult = false,
  });

  bool get isActive =>
      request.trim().isNotEmpty ||
      selectedTags.isNotEmpty ||
      mediaTypes.isNotEmpty ||
      formats.isNotEmpty ||
      includeAdult;

  RecommendationQuery copyWith({
    String? request,
    Set<String>? selectedTags,
    Set<String>? mediaTypes,
    Set<String>? formats,
    bool? includeAdult,
  }) {
    return RecommendationQuery(
      request: request ?? this.request,
      selectedTags: selectedTags ?? this.selectedTags,
      mediaTypes: mediaTypes ?? this.mediaTypes,
      formats: formats ?? this.formats,
      includeAdult: includeAdult ?? this.includeAdult,
    );
  }

  Set<String> inferredTags(Iterable<String> availableTags) {
    final normalizedRequest = _normalize(request);
    if (normalizedRequest.isEmpty) return {};

    return {
      for (final tag in availableTags)
        if (normalizedRequest.contains(_normalize(tag))) tag,
    };
  }

  Set<String> inferredFormats() {
    final text = _normalize(request);
    final formats = <String>{};

    if (_containsAny(text, ['tv', 'series', 'show', 'anime series'])) {
      formats.add('TV');
    }
    if (_containsAny(text, ['movie', 'film', 'cinematic'])) {
      formats.add('MOVIE');
    }
    if (_containsAny(text, ['ova', 'special'])) {
      formats.add('OVA');
    }
    if (_containsAny(text, ['ona', 'web anime'])) {
      formats.add('ONA');
    }
    if (_containsAny(text, ['manga', 'comic'])) {
      formats.add('MANGA');
    }
    if (_containsAny(text, ['novel', 'light novel', 'ln'])) {
      formats.add('NOVEL');
    }

    return formats;
  }

  Set<String> inferredMediaTypes() {
    final text = _normalize(request);
    final types = <String>{};

    if (_containsAny(text, ['anime', 'tv', 'movie', 'film', 'ova', 'ona'])) {
      types.add('ANIME');
    }
    if (_containsAny(text, ['manga', 'comic', 'novel', 'light novel', 'ln'])) {
      types.add('MANGA');
    }

    return types;
  }

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

  bool matchesText(MediaItem item) {
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
      'manga',
      'movie',
      'novel',
      'nsfw',
      'ona',
      'ova',
      'series',
      'show',
      'special',
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
}
