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
    final uri = Uri.parse('https://store.steampowered.com/api/storesearch/')
        .replace(
          queryParameters: {
            'term': trimmed,
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
    if (decoded is! Map<String, dynamic>) return const [];
    final appIds = SteamService.parseStoreSearchAppIds(
      decoded,
    ).take(safeLimit * 2);

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

    final safeLimit = limit.clamp(1, 6);
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

    return results;
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
