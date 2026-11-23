import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:majika/core/services/steam_service.dart';

typedef AiSearchHttpGet =
    Future<http.Response> Function(Uri url, {Map<String, String>? headers});

class AiSearchToolbox {
  final AiSearchHttpGet? httpGet;

  const AiSearchToolbox({this.httpGet});

  Future<List<Map<String, Object?>>> searchSteamGames(
    String query, {
    int limit = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final safeLimit = limit.clamp(1, 6);
    final appIds = <int>[];
    for (final term in SteamService.expandedSteamStoreSearchTerms(trimmed)) {
      final uri = Uri.parse('https://store.steampowered.com/api/storesearch/')
          .replace(
            queryParameters: {
              'term': term,
              'l': 'en',
              'cc': 'us',
              'category1': '998',
            },
          );
      final response = await _get(
        uri,
        headers: const {'User-Agent': 'Majika/1.0'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Steam store search returned HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) continue;
      for (final appId in SteamService.parseStoreSearchAppIds(decoded)) {
        if (!appIds.contains(appId)) {
          appIds.add(appId);
        }
        if (appIds.length >= safeLimit * 2) break;
      }
      if (appIds.length >= safeLimit * 2) break;
    }

    final items = <Map<String, Object?>>[];
    for (final appId in appIds) {
      final detailUri = Uri.parse(
        'https://store.steampowered.com/api/appdetails',
      ).replace(queryParameters: {'appids': '$appId', 'l': 'en', 'cc': 'us'});
      final detailResponse = await _get(
        detailUri,
        headers: const {'User-Agent': 'Majika/1.0'},
      ).timeout(const Duration(seconds: 20));
      if (detailResponse.statusCode < 200 || detailResponse.statusCode >= 300) {
        continue;
      }
      final detailJson = jsonDecode(detailResponse.body);
      if (detailJson is! Map<String, dynamic>) continue;
      final item = SteamService.parseAppDetails(detailJson, appId: appId);
      if (item == null) continue;
      items.add({
        'title': item.title,
        'subtitle': item.subtitle,
        'description': item.description ?? '',
        'tags': item.tags.take(6).toList(),
        'format': item.format,
        'rating': item.rating,
        'url': item.siteUrl,
      });
      if (items.length >= safeLimit) break;
    }

    return items;
  }

  Future<List<Map<String, Object?>>> searchWeb(
    String query, {
    int limit = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final safeLimit = limit.clamp(1, 20);
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': trimmed});
    final response = await _get(
      uri,
      headers: const {
        'User-Agent': 'Majika/1.0',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Web search returned HTTP ${response.statusCode}.');
    }

    final html = response.body;
    final titleMatches = RegExp(
      r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html);
    final snippetMatches = RegExp(
      r'class="result__snippet"[^>]*>(.*?)</(?:a|div)>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html).toList();

    final results = <Map<String, Object?>>[];
    var index = 0;
    for (final match in titleMatches) {
      final rawUrl = match.group(1)?.trim() ?? '';
      final rawTitle = match.group(2)?.trim() ?? '';
      if (rawUrl.isEmpty || rawTitle.isEmpty) continue;
      final title = _cleanHtml(rawTitle);
      if (title.isEmpty) continue;
      final snippet = index < snippetMatches.length
          ? _cleanHtml(snippetMatches[index].group(1) ?? '')
          : '';
      index += 1;
      results.add({
        'title': title,
        'snippet': snippet,
        'url': _decodeDuckDuckGoUrl(rawUrl),
      });
      if (results.length >= safeLimit) break;
    }

    if (results.isNotEmpty) return results;
    return _searchWikipedia(trimmed, limit: safeLimit);
  }

  Future<List<Map<String, Object?>>> searchGameComparison({
    required String request,
    required String reference,
    required bool vr,
  }) async {
    // One index can still provide evidence if the other is offline.
    final subject = reference.replaceAll('"', '').trim();
    final searches = [
      _comparisonArticles('$subject ${vr ? 'virtual reality ' : ''}video game'),
      searchWeb('Steam games like: $request', limit: 4),
    ];
    final groups = await Future.wait([
      for (final search in searches)
        search
            .timeout(const Duration(seconds: 10))
            .catchError((Object _) => <Map<String, Object?>>[]),
    ]);
    final seen = <String>{};
    return [
      for (final group in groups)
        for (final hit in group)
          if (seen.add(hit['url'].toString())) hit,
    ];
  }

  Future<List<Map<String, Object?>>> searchGameThemes(
    String request,
    String concepts,
  ) async {
    final words = RegExp(r'[\p{L}\p{N}]+', unicode: true);
    String keywords(String text, int limit) =>
        words.allMatches(text).take(limit).map((m) => m[0]!).join(' ');
    final terms = keywords(concepts, 2);
    if (terms.isEmpty) return const [];
    final topic = keywords(SteamService.requestTopic(request) ?? '', 4);
    for (final subject in {'$terms $topic'.trim(), terms}) {
      final hits = await _comparisonArticles(
        'hastemplate:"Infobox video game" $subject',
        gamePagesOnly: true,
      );
      if (hits.isNotEmpty) return hits;
    }
    return const [];
  }

  Future<List<Map<String, Object?>>> _comparisonArticles(
    String query, {
    bool gamePagesOnly = false,
  }) async {
    final uri = Uri.https('en.wikipedia.org', '/w/rest.php/v1/search/page', {
      'q': query,
      'limit': '15',
    });
    final response = await _get(
      uri,
      headers: const {'User-Agent': 'Majika/1.0', 'Accept': 'application/json'},
    );
    if (response.statusCode != 200) return const [];
    final pages = jsonDecode(response.body)['pages'] as List;
    final gameDescription = RegExp(
      r'\b(?:video|VR) game\b(?:$| (?:by|developed|released)\b)',
      caseSensitive: false,
    );
    return [
      for (final page in pages.whereType<Map>())
        if (page['title'] is String &&
            (gamePagesOnly ||
                gameDescription.hasMatch(
                  page['description']?.toString() ?? '',
                )))
          {
            'title': page['title'],
            'snippet': _cleanHtml(page['excerpt']?.toString() ?? ''),
            'url': Uri.https(
              'en.wikipedia.org',
              '/wiki/${page['key']}',
            ).toString(),
            'gameTitle': (page['title'] as String).replaceFirst(
              RegExp(r' \((?:\d{4} )?video game\)$'),
              '',
            ),
          },
    ].take(5).toList();
  }

  Future<List<Map<String, Object?>>> _searchWikipedia(
    String query, {
    required int limit,
  }) async {
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'srlimit': '$limit',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
    });
    final response = await _get(
      uri,
      headers: const {'User-Agent': 'Majika/1.0', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Wikipedia search returned HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    final queryData = decoded is Map ? decoded['query'] : null;
    final search = queryData is Map ? queryData['search'] : null;
    if (search is! List) return const [];
    return [
      for (final result in search)
        if (result is Map &&
            result['title']?.toString().trim().isNotEmpty == true)
          {
            'title': result['title'].toString().trim(),
            'snippet': _cleanHtml(result['snippet']?.toString() ?? ''),
            'url': Uri.https(
              'en.wikipedia.org',
              '/wiki/${result['title'].toString().replaceAll(' ', '_')}',
            ).toString(),
          },
    ];
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) {
    final getter = httpGet ?? http.get;
    return getter(uri, headers: headers);
  }

  String _decodeDuckDuckGoUrl(String rawUrl) {
    final decoded = Uri.decodeFull(rawUrl);
    final uri = Uri.tryParse(decoded);
    final redirect = uri?.queryParameters['uddg'];
    if (redirect != null && redirect.trim().isNotEmpty) {
      return Uri.decodeComponent(redirect);
    }
    return decoded;
  }

  String _cleanHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
