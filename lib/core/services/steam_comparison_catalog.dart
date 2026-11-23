import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:majika/core/ai/ai_console_log.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/services/search_spelling.dart';

typedef _Facet = ({String name, int id, String category});
typedef SteamComparisonResults = ({
  List<SteamBrowseHit> hits,
  List<String> titles,
  String reference,
  List<String> subjects,
});
typedef SteamBrowseHit = ({int id, Set<String> tags});

/// Joins a reference game's indexed subjects to live Steam tag intersections.
/// A reference may be a console exclusive. Only the resulting games need a
/// Steam listing.
class SteamComparisonCatalog {
  SteamComparisonCatalog(
    this._client,
    this._lookupTitleIds,
    this._nearbyTitleIds,
  );
  final Future<List<int>> Function(String title) _nearbyTitleIds;
  final Future<List<int>> Function(String title) _lookupTitleIds;
  final http.Client _client;
  Map<int, String>? _tagNames;

  Future<SteamComparisonResults> search(
    String reference,
    RecommendationQuery query,
  ) async {
    final (page, tags, initialIds) = await (
      _referencePage(reference),
      _tags(),
      _lookupTitleIds(reference),
    ).wait;
    final canonical = _gameTitle(page?['title'] as String? ?? reference);
    var seedIds = initialIds.isEmpty && _key(canonical) != _key(reference)
        ? await _lookupTitleIds(canonical)
        : initialIds;
    if (seedIds.isEmpty && page?['categories'] == null) {
      seedIds = await _nearbyTitleIds(reference);
    }
    final seedTags = seedIds.isEmpty
        ? const <int>[]
        : (await _tagIds([seedIds.first]))[seedIds.first] ?? <int>[];
    final facets = _subjects(page, tags, seedTags);
    final requestText = ' ${_key(query.request)} ';
    final articleIntro = ' ${_key(page?['extract'] as String? ?? '')} ';
    final requestWords = requestText.split(' ').toSet();
    final explicit = {
      ...query.selectedTags,
      ...query.aiSelectedTags,
    }.map(_key).toSet();
    int priority(_Facet facet) {
      final key = _key(facet.name);
      if (requestText.contains(' $key ')) return 40;
      if (explicit.contains(key)) return 35;
      // Break ties between grounded subjects using the user's vocabulary.
      if (key.length >= 6 &&
          requestWords.any((w) => w.startsWith(key.substring(0, 5)))) {
        return 30;
      }
      final steamRank = seedTags.indexOf(facet.id);
      if (steamRank >= 0) return 25 - steamRank;
      if (articleIntro.contains(' $key ')) return 10;
      return _key(facet.category).startsWith('$key video games') ? 1 : 0;
    }

    facets.sort((a, b) {
      final rank = priority(b).compareTo(priority(a));
      return rank != 0 ? rank : a.name.compareTo(b.name);
    });
    final hits = <int, Set<String>>{};
    final titles = <String>{};
    if (facets.length >= 2) {
      final anchor = facets.first;
      final others = facets.skip(1).take(3).toList();
      AiConsoleLog.current?.addDetail(
        'Comparing “$canonical” using ${anchor.name} paired with ${others.map((f) => f.name).join(', ')}.',
      );
      final focusSecondFacet =
          priority(anchor) >= 30 && priority(others.first) >= 30;
      final (storeGroups, articleGroups) = await (
        Future.wait([for (final other in others) _browse(anchor, other, tags)]),
        Future.wait([
          for (var i = 0; i < others.length; i++)
            for (var j = i + 1; j < others.length; j++)
              if (anchor.category.isNotEmpty &&
                  others[i].category.isNotEmpty &&
                  others[j].category.isNotEmpty)
                _relatedPages([anchor, others[i], others[j]], canonical),
        ]),
      ).wait;
      // Preserve the first results of each distinct intersection even when
      // one popular genre has hundreds of hits.
      for (var index = 0; index < 10; index++) {
        for (final group in storeGroups) {
          if (index >= group.length) continue;
          final hit = group[index];
          if (seedIds.contains(hit.id)) continue;
          if (focusSecondFacet && !hit.tags.contains(others.first.name)) {
            continue;
          }
          (hits[hit.id] ??= {}).addAll(hit.tags);
        }
        for (final group in articleGroups) {
          if (index < group.length) titles.add(group[index]);
        }
      }
    }
    return (
      hits: [for (final e in hits.entries.take(20)) (id: e.key, tags: e.value)],
      titles: titles.take(12).toList(),
      reference: canonical,
      subjects: facets.take(4).map((f) => f.name).toList(),
    );
  }

  static List<_Facet> _subjects(
    Map? page,
    Map<int, String> tags,
    List<int> seedTags,
  ) {
    final byName = {for (final tag in tags.entries) _key(tag.value): tag.key};
    final byId = <int, _Facet>{};
    void add(int? id, String category) {
      final name = tags[id];
      if (id == null || name == null || byId.containsKey(id)) return;
      if (const {
        'singleplayer',
        'multiplayer',
        '2d',
        '3d',
        'indie',
      }.contains(_key(name))) {
        return;
      }
      byId[id] = (id: id, name: name, category: category);
    }

    final categories = (page?['categories'] as List? ?? const [])
        .whereType<Map>();
    for (final entry in categories) {
      final category = '${entry['title']}'.replaceFirst('Category:', '');
      final subject = _key(
        category
            .replaceFirst(
              RegExp(
                r'^Video games (?:about|with|featuring) ',
                caseSensitive: false,
              ),
              '',
            )
            .replaceFirst(
              RegExp(r' (?:video )?games$', caseSensitive: false),
              '',
            ),
      );
      add(
        byName[subject] ?? byName[subject.replaceFirst(RegExp(r's$'), '')],
        category,
      );
    }
    for (final id in seedTags) {
      add(id, '');
    }
    return byId.values.toList();
  }

  static String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  Future<String?> correctedSpelling(String text) async {
    if (text.length > 120) return null;
    final lookup = await _wiki({
      'list': 'search',
      'srsearch': text,
      'srinfo': 'suggestion',
      'srprop': '',
      'srlimit': '1',
    });
    final suggested = lookup['searchinfo']?['suggestion'];
    return suggested is String &&
            suggested != text &&
            isCloseSearchSpelling(text, suggested)
        ? suggested
        : null;
  }

  Future<Map?> _referencePage(String reference) async {
    if (reference.length > 120) return null;
    final lookup = await _wiki({
      'list': 'search',
      'srsearch': reference,
      'srprop': '',
      'srinfo': 'suggestion',
      'srlimit': '6',
    });
    final corrected = lookup['searchinfo']?['suggestion'] as String?;
    final subject =
        corrected != null && isCloseSearchSpelling(reference, corrected)
        ? corrected
        : reference;
    final names = [
      for (final entry
          in (lookup['search'] as List? ?? const []).whereType<Map>())
        if (entry['title'] is String &&
            _key(_gameTitle(entry['title'])) == _key(subject))
          entry['title'] as String,
    ];
    final searchBySpelling = names.isEmpty && subject != reference;
    final pages = await _wiki({
      if (searchBySpelling) ...{
        'generator': 'search',
        'gsrsearch': subject,
        'gsrlimit': '4',
      } else
        'titles': {...names, subject, '$subject (video game)'}.join('|'),
      'redirects': '1',
      'prop': 'categories|extracts',
      'exintro': '1',
      'explaintext': '1',
      'exsentences': '4',
      'cllimit': 'max',
      'clshow': '!hidden',
    });
    for (final page
        in (pages['pages'] as Map? ?? const {}).values.whereType<Map>()) {
      if (searchBySpelling &&
          _key(_gameTitle(page['title'] ?? '')) != _key(subject)) {
        continue;
      }
      final categories = page['categories'] as List? ?? const [];
      if (categories.any(
        (c) => RegExp(
          r'^Category:(?:[0-9]{4}|Upcoming) video games',
          caseSensitive: false,
        ).hasMatch('${c['title']}'),
      )) {
        return page;
      }
    }
    return {'title': subject};
  }

  static String _gameTitle(String title) => title.replaceFirst(
    RegExp(r' \((?:\d{4} )?video game\)$', caseSensitive: false),
    '',
  );

  Future<List<String>> _relatedPages(
    List<_Facet> facets,
    String reference,
  ) async {
    final search = [
      'hastemplate:"Infobox video game"',
      for (final f in facets) 'incategory:"${f.category.replaceAll('"', '')}"',
    ].join(' ');
    final result = await _wiki({
      'list': 'search',
      'srsearch': search,
      'srlimit': '10',
      'srprop': '',
    });
    return [
      for (final entry
          in (result['search'] as List? ?? const []).whereType<Map>())
        if (entry['title'] is String && entry['title'] != reference)
          _gameTitle(entry['title']),
    ];
  }

  Future<List<SteamBrowseHit>> _browse(
    _Facet a,
    _Facet b,
    Map<int, String> tags,
  ) async {
    final result = await _read(
      Uri.https('store.steampowered.com', '/search/results/', {
        'tags': '${a.id},${b.id}',
        'category1': '998',
        'infinite': '1',
        'count': '15',
        'l': 'english',
        'cc': 'us',
      }),
    );
    final html = result is Map ? result['results_html'] : null;
    if (html is! String) return [];
    return [
      for (final row in RegExp(
        r'<a\b[^>]*\bdata-ds-appid="(\d+)"[^>]*>',
        dotAll: true,
      ).allMatches(html))
        if (row[0]!.contains('data-ds-itemkey="App_${row[1]}"'))
          (
            id: int.parse(row[1]!),
            tags: {
              a.name,
              b.name,
              for (final id
                  in (RegExp(
                            r'data-ds-tagids="\[([\d, ]*)\]"',
                          ).firstMatch(row[0]!)?[1] ??
                          '')
                      .split(','))
                if (tags[int.tryParse(id.trim())] case final String tag) tag,
            },
          ),
    ];
  }

  Future<Map<int, List<String>>> communityTags(Iterable<int> ids) async {
    if (ids.isEmpty || _tagNames == null) return {};
    final results = await _tagIds(ids);
    return {
      for (final e in results.entries)
        e.key: [
          for (final id in e.value)
            if (_tagNames![id] case final String name) name,
        ],
    };
  }

  Future<Map<int, List<int>>> _tagIds(Iterable<int> ids) async {
    final data = await _read(
      Uri.https('api.steampowered.com', '/IStoreBrowseService/GetItems/v1/', {
        'input_json': jsonEncode({
          'ids': [
            for (final id in ids) {'appid': id},
          ],
          'context': {'language': 'english', 'country_code': 'US'},
          'data_request': {'include_tag_count': 12},
        }),
      }),
    );
    if (data is! Map || data['response'] is! Map) return {};
    final items = data['response']['store_items'];
    if (items is! List) return {};
    return {
      for (final item in items.whereType<Map>())
        if (item['id'] is int && item['tagids'] is List)
          item['id'] as int: (item['tagids'] as List).whereType<int>().toList(),
    };
  }

  Future<Map<int, String>> _tags() async {
    if (_tagNames != null) return _tagNames!;
    final data = await _read(
      Uri.https('store.steampowered.com', '/tagdata/populartags/english'),
    );
    if (data is! List) return {};
    final tags = {
      for (final tag in data.whereType<Map>())
        if (tag['tagid'] is int && tag['name'] is String)
          tag['tagid'] as int: tag['name'] as String,
    };
    if (tags.isNotEmpty) _tagNames = tags;
    return tags;
  }

  Future<Map> _wiki(Map<String, String> params) async {
    final data = await _read(
      Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        ...params,
      }),
    );
    return data is Map && data['query'] is Map
        ? data['query'] as Map
        : const {};
  }

  Future<Object?> _read(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'User-Agent': 'Majika/1.0'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } on Exception {
      // Each index can fail independently. Keep evidence from other sources.
    }
    return null;
  }
}
