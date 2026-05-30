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
Favorite characters: ${profile.favoriteCharacters.take(8).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(8).join(', ')}
High rated examples: ${profile.highRatedItems.map((item) => item.title).take(8).join(', ')}
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

    final tagList = availableTags.take(260).join(', ');
    final prompt =
        '''
You turn recommendation search text into structured AniList filters.
Return JSON only. No markdown. No explanation.
Allowed mediaTypes: ${RecommendationQuery.allMediaTypes.join(', ')}
Allowed formats: ${RecommendationQuery.allFormats.join(', ')}
Allowed tags: $tagList
Schema:
{"tags":["Romance"],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"optional leftover search terms"}
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
        maxTokens: 768,
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
Favorite characters: ${profile.favoriteCharacters.take(6).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(6).join(', ')}
Recommendation: ${recommendation.item.title}
Tags: ${recommendation.item.tags.join(', ')}
Signals: ${recommendation.signals.join(', ')}
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
    final jsonText = _extractJsonObject(response);
    if (jsonText == null) return null;

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;

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

  String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null) item.toString().trim(),
    ].where((item) => item.isNotEmpty).toList();
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

    final options = recommendations.take(8).map((recommendation) {
      final item = recommendation.item;
      return {
        'id': item.id,
        'title': item.title,
        'score': recommendation.matchScore.round(),
        'tags': item.tags.take(8).toList(),
        'format': item.format,
        'signals': recommendation.signals.take(6).toList(),
      };
    }).toList();
    final prompt =
        '''
Pick the single best recommendation for this user from the options.
Return JSON only with this schema: {"id":"anilist_123","reason":"short reason"}
User taste: ${profile.primaryTaste}
Favorite tags: ${profile.favoriteGenres.join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(8).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(8).join(', ')}
Search request: ${query.request}
User-selected tags: ${query.selectedTags.join(', ')}
AI-selected tags: ${query.aiSelectedTags.join(', ')}
Options: ${jsonEncode(options)}
''';

    try {
      final response = await _generateText(
        prompt,
        maxTokens: 512,
        settings: settings,
      );
      final jsonText = _extractJsonObject(response);
      if (jsonText == null) return recommendations.first;
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return recommendations.first;
      final id = decoded['id']?.toString();
      final reason = decoded['reason']?.toString().trim();
      Recommendation? chosen;
      for (final recommendation in recommendations) {
        if (recommendation.item.id == id) {
          chosen = recommendation;
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
