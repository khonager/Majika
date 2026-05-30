import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
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
}

class FlutterGemmaLocalAiService implements LocalAiService {
  final LocalAiService fallback;
  final Future<String> Function(String prompt, int maxTokens)? textGenerator;

  const FlutterGemmaLocalAiService({
    this.fallback = const DeterministicLocalAiService(),
    this.textGenerator,
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
    if (!isConfigured) return fallback.summarizeProfile(profile);

    final prompt =
        '''
Summarize this AniList taste profile in one concise sentence.
Favorite tags: ${profile.favoriteGenres.join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(8).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(8).join(', ')}
High rated examples: ${profile.highRatedItems.map((item) => item.title).take(8).join(', ')}
''';

    try {
      final text = await _generateText(prompt, maxTokens: 512);
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
    if (!query.isActive || !isConfigured) {
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
Currently selected formats: ${query.formats.join(', ')}
Currently selected media types: ${query.mediaTypes.join(', ')}
Adult content selected: ${query.includeAdult}
''';

    try {
      final response = await _generateText(prompt, maxTokens: 768);
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
    if (!isConfigured) {
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
      final text = await _generateText(prompt, maxTokens: 384);
      return text.trim().isEmpty ? recommendation.reason : text.trim();
    } catch (_) {
      return fallback.explainRecommendation(profile, recommendation);
    }
  }

  Future<String> _generateText(String prompt, {required int maxTokens}) async {
    final generator = textGenerator;
    if (generator != null) {
      return generator(prompt, maxTokens);
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
        modelType: ModelType.functionGemma,
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
      selectedTags: {...original.selectedTags, ...tags},
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
}
