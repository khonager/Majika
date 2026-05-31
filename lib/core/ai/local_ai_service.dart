import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';

abstract class LocalAiService {
  bool get isConfigured;

  Future<String> summarizeProfile(TasteProfile profile);

  Future<RecommendationQuery> interpretRecommendationRequest(
    RecommendationQuery query, {
    required Iterable<String> availableTags,
  });

  Future<String> explainRecommendation(
    TasteProfile profile,
    Recommendation recommendation,
  );

  Future<Recommendation?> chooseTopRecommendation(
    TasteProfile profile,
    List<Recommendation> recommendations, {
    required RecommendationQuery query,
  });
}

class DeterministicLocalAiService implements LocalAiService {
  const DeterministicLocalAiService();

  @override
  bool get isConfigured => false;

  @override
  Future<String> summarizeProfile(TasteProfile profile) async {
    return profile.summary;
  }

  @override
  Future<RecommendationQuery> interpretRecommendationRequest(
    RecommendationQuery query, {
    required Iterable<String> availableTags,
  }) async {
    return query.withInferredSelections(availableTags);
  }

  @override
  Future<String> explainRecommendation(
    TasteProfile profile,
    Recommendation recommendation,
  ) async {
    return recommendation.reason;
  }

  @override
  Future<Recommendation?> chooseTopRecommendation(
    TasteProfile profile,
    List<Recommendation> recommendations, {
    required RecommendationQuery query,
  }) async {
    return recommendations.isEmpty ? null : recommendations.first;
  }
}

class FlutterGemmaLocalAiService implements LocalAiService {
  final LocalAiService fallback;
  final Future<String> Function(String prompt, int maxTokens)? textGenerator;
  final Future<LocalAiRuntimeSettings> Function()? settingsLoader;
  final Future<http.Response> Function(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  })?
  httpPost;

  const FlutterGemmaLocalAiService({
    this.fallback = const DeterministicLocalAiService(),
    this.textGenerator,
    this.settingsLoader,
    this.httpPost,
  });

  @override
  bool get isConfigured {
    if (textGenerator != null) return true;
    try {
      return FlutterGemma.hasActiveModel();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> summarizeProfile(TasteProfile profile) async {
    final settings = await _runtimeSettings();
    if (!settings.useLocalAi && textGenerator == null) {
      return fallback.summarizeProfile(profile);
    }

    final prompt =
        '''
Summarize this AniList taste profile in one concise sentence.
Favorite tags: ${profile.favoriteGenres.join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(settings.contextItemLimit).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(settings.contextItemLimit).join(', ')}
High rated examples: ${profile.highRatedItems.map((item) => item.title).take(settings.contextItemLimit).join(', ')}
''';

    try {
      final text = await _generateText(
        prompt,
        maxTokens: 512,
        settings: settings,
      );
      return text.trim().isEmpty ? profile.summary : text.trim();
    } catch (_) {
      return fallback.summarizeProfile(profile);
    }
  }

  @override
  Future<RecommendationQuery> interpretRecommendationRequest(
    RecommendationQuery query, {
    required Iterable<String> availableTags,
  }) async {
    final settings = await _runtimeSettings();
    if (!query.isActive ||
        (!settings.useLocalAi && textGenerator == null) ||
        !settings.useAiForSearch) {
      return fallback.interpretRecommendationRequest(
        query,
        availableTags: availableTags,
      );
    }

    final tagList = _promptTagList(
      query: query,
      availableTags: availableTags,
      limit: settings.contextItemLimit,
    ).join(', ');
    final prompt =
        '''
You turn recommendation search text into structured AniList filters.
Return JSON only. No markdown. No explanation.
Return one object with exactly these keys: tags, formats, mediaTypes, includeAdult, searchText.
Use empty arrays when no allowed tag, format, or media type clearly matches.
Keep leftover natural-language terms in searchText.
Allowed mediaTypes: ${RecommendationQuery.allMediaTypes.join(', ')}
Allowed formats: ${RecommendationQuery.allFormats.join(', ')}
Allowed tags: $tagList
User request: ${query.request}
Currently selected tags: ${query.selectedTags.join(', ')}
Previously AI selected tags: ${query.aiSelectedTags.join(', ')}
Currently selected formats: ${query.formats.join(', ')}
Currently selected media types: ${query.mediaTypes.join(', ')}
Adult content selected: ${query.includeAdult}
''';

    try {
      final response = await _generateText(
        prompt,
        maxTokens: 1024,
        settings: settings,
      );
      final interpreted = _queryFromModelJson(
        response,
        original: query,
        availableTags: availableTags,
      );
      if (interpreted == null) {
        return fallback.interpretRecommendationRequest(
          query,
          availableTags: availableTags,
        );
      }
      return interpreted;
    } catch (_) {
      return fallback.interpretRecommendationRequest(
        query,
        availableTags: availableTags,
      );
    }
  }

  @override
  Future<String> explainRecommendation(
    TasteProfile profile,
    Recommendation recommendation,
  ) async {
    final settings = await _runtimeSettings();
    if (!settings.useLocalAi && textGenerator == null) {
      return fallback.explainRecommendation(profile, recommendation);
    }

    final prompt =
        '''
Explain in one short sentence why this recommendation fits.
Profile: ${profile.primaryTaste}
Favorite tags: ${profile.favoriteGenres.join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(settings.contextItemLimit).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(settings.contextItemLimit).join(', ')}
Recommendation: ${recommendation.item.title}
Tags: ${recommendation.item.tags.take(settings.contextItemLimit).join(', ')}
Signals: ${recommendation.signals.take(settings.contextItemLimit).join(', ')}
''';

    try {
      final text = await _generateText(
        prompt,
        maxTokens: 384,
        settings: settings,
      );
      return text.trim().isEmpty ? recommendation.reason : text.trim();
    } catch (_) {
      return fallback.explainRecommendation(profile, recommendation);
    }
  }

  Future<String> _generateText(
    String prompt, {
    required int maxTokens,
    required LocalAiRuntimeSettings settings,
  }) async {
    final generator = textGenerator;
    if (generator != null) {
      return generator(prompt, maxTokens);
    }

    if (settings.usesExternalServer) {
      return _generateExternalText(
        prompt,
        maxTokens: maxTokens,
        settings: settings,
      );
    }

    if (!isConfigured) {
      throw StateError('No local AI model is configured.');
    }

    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.cpu,
    );
    try {
      final chat = await model.createChat(
        temperature: 0.1,
        topK: 1,
        tokenBuffer: 128,
        modelType: _activeModelType(),
      );
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await chat.generateChatResponse();
      return switch (response) {
        TextResponse(:final token) => token,
        _ => response.toString(),
      };
    } finally {
      await model.close();
    }
  }

  Future<String> _generateExternalText(
    String prompt, {
    required int maxTokens,
    required LocalAiRuntimeSettings settings,
  }) async {
    final post = httpPost ?? http.post;
    final response = await post(
      settings.chatCompletionsUri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': settings.serverModel,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.1,
        'max_tokens': maxTokens,
        'stream': false,
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Local AI server returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Local AI response was not a JSON object.');
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Local AI response did not include choices.');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw const FormatException('Local AI choice was not a JSON object.');
    }

    final message = firstChoice['message'];
    if (message is Map<String, dynamic>) {
      final content = message['content'];
      if (content != null) return content.toString();
    }

    final text = firstChoice['text'];
    if (text != null) return text.toString();

    throw const FormatException('Local AI response did not include text.');
  }

  Future<LocalAiRuntimeSettings> _runtimeSettings() {
    final loader = settingsLoader;
    if (loader != null) return loader();
    if (textGenerator != null) {
      return Future.value(const LocalAiRuntimeSettings.defaults(enabled: true));
    }
    return LocalAiRuntimeSettings.load(defaultEnabled: textGenerator != null);
  }

  ModelType _activeModelType() {
    final activeModel =
        FlutterGemmaPlugin.instance.modelManager.activeInferenceModel;
    return activeModel is InferenceModelSpec
        ? activeModel.modelType
        : ModelType.gemmaIt;
  }

  RecommendationQuery? _queryFromModelJson(
    String response, {
    required RecommendationQuery original,
    required Iterable<String> availableTags,
  }) {
    Map<String, dynamic>? decoded;
    for (final candidate in _jsonObjects(response)) {
      if (_looksLikeQueryJson(candidate)) {
        decoded = candidate;
      }
    }
    if (decoded == null) return null;

    final availableTagSet = availableTags.toSet();
    final tags = _stringList(
      decoded['tags'],
    ).where((tag) => availableTagSet.contains(tag)).toSet();
    final formats = _stringList(
      decoded['formats'],
    ).where(RecommendationQuery.allFormats.contains).toSet();
    final mediaTypes = _stringList(
      decoded['mediaTypes'],
    ).where(RecommendationQuery.allMediaTypes.contains).toSet();
    final searchText = decoded['searchText']?.toString().trim();

    return original.copyWith(
      request: searchText == null || searchText.isEmpty
          ? original.request
          : searchText,
      selectedTags: original.selectedTags,
      aiSelectedTags: tags,
      formats: formats.isEmpty ? original.formats : formats,
      mediaTypes: mediaTypes.isEmpty ? original.mediaTypes : mediaTypes,
      includeAdult: original.includeAdult || decoded['includeAdult'] == true,
    );
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null) item.toString().trim(),
    ].where((item) => item.isNotEmpty).toList();
  }

  List<String> _promptTagList({
    required RecommendationQuery query,
    required Iterable<String> availableTags,
    required int limit,
  }) {
    final tags = <String>{
      ...query.selectedTags,
      ...query.aiSelectedTags,
      ...query.inferredTags(availableTags),
      ...RecommendationQuery.browsableTags,
    };

    for (final tag in availableTags) {
      if (tags.length >= limit) break;
      tags.add(tag);
    }

    return tags.take(limit).toList();
  }

  bool _looksLikeQueryJson(Map<String, dynamic> decoded) {
    return decoded.containsKey('tags') ||
        decoded.containsKey('formats') ||
        decoded.containsKey('mediaTypes') ||
        decoded.containsKey('includeAdult') ||
        decoded.containsKey('searchText');
  }

  Iterable<Map<String, dynamic>> _jsonObjects(String text) sync* {
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;

    for (var index = 0; index < text.length; index++) {
      final char = text[index];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
        continue;
      }

      if (char == '{') {
        if (depth == 0) start = index;
        depth++;
        continue;
      }

      if (char == '}' && depth > 0) {
        depth--;
        if (depth == 0 && start != -1) {
          final jsonText = text.substring(start, index + 1);
          try {
            final decoded = jsonDecode(jsonText);
            if (decoded is Map<String, dynamic>) yield decoded;
          } catch (_) {
            // Keep scanning; small local models may emit several fragments.
          }
          start = -1;
        }
      }
    }
  }

  @override
  Future<Recommendation?> chooseTopRecommendation(
    TasteProfile profile,
    List<Recommendation> recommendations, {
    required RecommendationQuery query,
  }) async {
    if (recommendations.isEmpty) return null;
    final settings = await _runtimeSettings();
    if (!settings.useLocalAi && textGenerator == null) {
      return fallback.chooseTopRecommendation(
        profile,
        recommendations,
        query: query,
      );
    }

    final optionLimit = (settings.contextItemLimit / 4).round().clamp(3, 6);
    final tagLimit = (settings.contextItemLimit / 3).round().clamp(4, 8);
    final signalLimit = (settings.contextItemLimit / 6).round().clamp(2, 4);
    final options = recommendations.take(optionLimit).map((recommendation) {
      final item = recommendation.item;
      return {
        'id': item.id,
        'title': item.title,
        'score': recommendation.matchScore.round(),
        'tags': item.tags.take(tagLimit).toList(),
        'format': item.format,
        'signals': recommendation.signals.take(signalLimit).toList(),
      };
    }).toList();
    final prompt =
        '''
Pick the single best recommendation for this user from the options.
Return JSON only. Use exactly these keys: id, reason. The id must match one option id.
User taste: ${profile.primaryTaste}
Favorite tags: ${profile.favoriteGenres.take(settings.contextItemLimit).join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(signalLimit).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(signalLimit).join(', ')}
Search request: ${query.request}
User-selected tags: ${query.selectedTags.join(', ')}
AI-selected tags: ${query.aiSelectedTags.join(', ')}
Options: ${jsonEncode(options)}
''';

    try {
      final response = await _generateText(
        prompt,
        maxTokens: 1024,
        settings: settings,
      );
      Recommendation? chosen;
      String? reason;
      for (final candidate in _jsonObjects(response)) {
        final id = candidate['id']?.toString();
        for (final recommendation in recommendations) {
          if (recommendation.item.id == id) {
            chosen = recommendation;
            reason = candidate['reason']?.toString().trim();
            break;
          }
        }
        if (chosen != null) {
          break;
        }
      }
      if (chosen == null) return recommendations.first;
      return chosen.copyWith(
        reason: reason == null || reason.isEmpty ? chosen.reason : reason,
        isAiPick: true,
      );
    } catch (_) {
      return fallback.chooseTopRecommendation(
        profile,
        recommendations,
        query: query,
      );
    }
  }
}
