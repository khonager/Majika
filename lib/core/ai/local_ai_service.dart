import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:majika/core/ai/ai_console_log.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';

final Object localAiConsoleLogZoneKey = Object();
final Object manualAiRequestHandlerZoneKey = Object();

typedef ManualAiRequestHandler =
    Future<String> Function(ManualAiRequest request);

class ManualAiRequest {
  final String prompt;
  final int maxTokens;
  final String mode;
  final String provider;

  const ManualAiRequest({
    required this.prompt,
    required this.maxTokens,
    required this.mode,
    required this.provider,
  });
}

abstract class LocalAiService {
  bool get isConfigured;

  Future<String> summarizeProfile(TasteProfile profile);

  Future<RecommendationQuery> interpretRecommendationRequest(
    RecommendationQuery query, {
    required Iterable<String> availableTags,
    String serviceName = 'AniList',
    Iterable<String> allowedMediaTypes = RecommendationQuery.aniListMediaTypes,
    Iterable<String> allowedFormats = RecommendationQuery.aniListFormats,
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

  Future<Recommendation?> chooseHomeRecommendation(
    List<TasteProfile> profiles,
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
    String serviceName = 'AniList',
    Iterable<String> allowedMediaTypes = RecommendationQuery.aniListMediaTypes,
    Iterable<String> allowedFormats = RecommendationQuery.aniListFormats,
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

  @override
  Future<Recommendation?> chooseHomeRecommendation(
    List<TasteProfile> profiles,
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
Summarize this ${profile.serviceName} taste profile in one concise sentence.
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
    String serviceName = 'AniList',
    Iterable<String> allowedMediaTypes = RecommendationQuery.aniListMediaTypes,
    Iterable<String> allowedFormats = RecommendationQuery.aniListFormats,
  }) async {
    final settings = await _runtimeSettings();
    if (!query.isActive ||
        (!settings.useLocalAi && textGenerator == null) ||
        !settings.useAiForSearch) {
      return fallback.interpretRecommendationRequest(
        query,
        availableTags: availableTags,
        serviceName: serviceName,
        allowedMediaTypes: allowedMediaTypes,
        allowedFormats: allowedFormats,
      );
    }

    final tagList = _promptTagList(
      query: query,
      availableTags: availableTags,
      limit: settings.contextItemLimit,
    ).join(', ');
    final prompt =
        '''
You turn recommendation search text into structured $serviceName filters.
Return JSON only. No markdown. No explanation.
Return one object with exactly these keys: tags, formats, mediaTypes, includeAdult, searchText.
Use empty arrays when no allowed tag, format, or media type clearly matches.
Keep leftover natural-language terms in searchText.
Allowed mediaTypes: ${allowedMediaTypes.join(', ')}
Allowed formats: ${allowedFormats.join(', ')}
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
        allowedMediaTypes: allowedMediaTypes,
        allowedFormats: allowedFormats,
      );
      if (interpreted == null) {
        return fallback.interpretRecommendationRequest(
          query,
          availableTags: availableTags,
          serviceName: serviceName,
          allowedMediaTypes: allowedMediaTypes,
          allowedFormats: allowedFormats,
        );
      }
      return interpreted;
    } catch (_) {
      return fallback.interpretRecommendationRequest(
        query,
        availableTags: availableTags,
        serviceName: serviceName,
        allowedMediaTypes: allowedMediaTypes,
        allowedFormats: allowedFormats,
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
    final log = _currentConsoleLog;
    log?.addSection('Prompt', prompt);
    if (generator != null) {
      final response = await generator(prompt, maxTokens);
      log?.addSection('Response', response);
      return response;
    }

    if (settings.usesManualAi) {
      final handler = _currentManualAiRequestHandler;
      if (handler == null) {
        throw StateError('Manual AI mode has no copy/paste handler.');
      }
      log?.addLine('Manual copy/paste mode is waiting for a response.');
      final response = await handler(
        ManualAiRequest(
          prompt: prompt,
          maxTokens: maxTokens,
          mode: settings.mode,
          provider: settings.provider,
        ),
      );
      log?.addSection('Manual response', response);
      return response;
    }

    if (settings.usesExternalServer || settings.usesExternalCloud) {
      return _generateExternalText(
        prompt,
        maxTokens: maxTokens,
        settings: settings,
      );
    }

    if (!isConfigured) {
      throw StateError('No local AI model is configured.');
    }

    final preferredBackend = _safeOnDeviceBackend(settings.preferredBackend);
    try {
      final response = await _generateOnDeviceText(
        prompt,
        maxTokens: maxTokens,
        preferredBackend: preferredBackend,
      );
      log?.addSection('Response', response);
      return response;
    } catch (_) {
      if (preferredBackend == null ||
          preferredBackend == PreferredBackend.cpu) {
        rethrow;
      }
      final response = await _generateOnDeviceText(
        prompt,
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );
      log?.addSection('Response', response);
      return response;
    }
  }

  Future<String> _generateOnDeviceText(
    String prompt, {
    required int maxTokens,
    required PreferredBackend? preferredBackend,
  }) async {
    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
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

  PreferredBackend? _safeOnDeviceBackend(PreferredBackend? preferredBackend) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return PreferredBackend.cpu;
    }
    return preferredBackend;
  }

  Future<String> _generateExternalText(
    String prompt, {
    required int maxTokens,
    required LocalAiRuntimeSettings settings,
  }) async {
    final post = httpPost ?? http.post;
    final isCloud = settings.usesExternalCloud;
    final log = _currentConsoleLog;
    final apiKey = settings.cloudApiKey.trim();
    if (isCloud && apiKey.isEmpty) {
      throw StateError('No ${settings.cloudProvider} API key is configured.');
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (isCloud) 'Authorization': 'Bearer $apiKey',
      if (isCloud && settings.cloudProvider == 'OpenRouter') ...{
        'HTTP-Referer': 'https://majika.local',
        'X-OpenRouter-Title': 'Majika',
      },
    };
    final endpoint = isCloud
        ? settings.cloudChatCompletionsUri
        : settings.localChatCompletionsUri;
    final model = isCloud ? settings.cloudModel : settings.serverModel;
    log?.addLine(
      'Sending request to ${isCloud ? settings.cloudProvider : 'local server'}: $model',
    );
    final response = await post(
      endpoint,
      headers: headers,
      body: jsonEncode({
        'model': model,
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
        '${isCloud ? settings.cloudProvider : 'Local AI server'} returned HTTP ${response.statusCode}: ${response.body}',
      );
    }
    log?.addLine('Received HTTP ${response.statusCode}.');

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
      if (content != null) {
        final text = content.toString();
        log?.addSection('Response', text);
        return text;
      }
    }

    final text = firstChoice['text'];
    if (text != null) {
      final value = text.toString();
      log?.addSection('Response', value);
      return value;
    }

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

  AiConsoleLog? get _currentConsoleLog {
    final value = Zone.current[localAiConsoleLogZoneKey];
    return value is AiConsoleLog ? value : null;
  }

  ManualAiRequestHandler? get _currentManualAiRequestHandler {
    final value = Zone.current[manualAiRequestHandlerZoneKey];
    return value is ManualAiRequestHandler ? value : null;
  }

  RecommendationQuery? _queryFromModelJson(
    String response, {
    required RecommendationQuery original,
    required Iterable<String> availableTags,
    required Iterable<String> allowedMediaTypes,
    required Iterable<String> allowedFormats,
  }) {
    Map<String, dynamic>? decoded;
    for (final candidate in _jsonObjects(response)) {
      if (_looksLikeQueryJson(candidate)) {
        decoded = candidate;
      }
    }
    if (decoded == null) return null;

    final availableTagSet = _canonicalLookup(availableTags);
    final tags = _stringList(decoded['tags'])
        .map((tag) => availableTagSet[_canonicalKey(tag)])
        .whereType<String>()
        .toSet();
    final allowedFormatSet = _canonicalLookup(allowedFormats);
    final allowedMediaTypeSet = _canonicalLookup(allowedMediaTypes);
    final modelFormats = _stringList(decoded['formats'])
        .map((format) => allowedFormatSet[_canonicalKey(format)])
        .whereType<String>()
        .toSet();
    final modelMediaTypes = _stringList(decoded['mediaTypes'])
        .map((type) => allowedMediaTypeSet[_canonicalKey(type)])
        .whereType<String>()
        .toSet();
    final searchText = decoded['searchText']?.toString().trim();
    final ruleInterpreted = original.withInferredSelections(availableTags);
    final formats = {...ruleInterpreted.formats, ...modelFormats};
    final mediaTypes = {...ruleInterpreted.mediaTypes, ...modelMediaTypes};

    return original.copyWith(
      request: searchText == null || searchText.isEmpty
          ? original.request
          : searchText,
      selectedTags: original.selectedTags,
      aiSelectedTags: {...ruleInterpreted.aiSelectedTags, ...tags},
      formats: formats,
      mediaTypes: mediaTypes,
      includeAdult:
          ruleInterpreted.includeAdult || decoded['includeAdult'] == true,
    );
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null) item.toString().trim(),
    ].where((item) => item.isNotEmpty).toList();
  }

  Map<String, String> _canonicalLookup(Iterable<String> values) {
    return {
      for (final value in values)
        if (value.trim().isNotEmpty) _canonicalKey(value): value,
    };
  }

  String _canonicalKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
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
    final requestedFormats = query.effectiveFormats();
    final requireLocalCoOp = query.infersLocalCoOp;
    final selectableRecommendations = _formatEligibleRecommendations(
      recommendations,
      requestedFormats,
      requireLocalCoOp: requireLocalCoOp,
    );
    if (!settings.useLocalAi && textGenerator == null) {
      return fallback.chooseTopRecommendation(
        profile,
        selectableRecommendations,
        query: query,
      );
    }

    final optionLimit = (settings.contextItemLimit / 4).round().clamp(3, 6);
    final tagLimit = (settings.contextItemLimit / 3).round().clamp(4, 8);
    final signalLimit = (settings.contextItemLimit / 6).round().clamp(2, 4);
    final optionTags = {
      for (final recommendation in selectableRecommendations)
        for (final tag in recommendation.item.tags) tag,
    };
    final requestTags = {
      ...query.selectedTags,
      ...query.aiSelectedTags,
      ...query.inferredTags(optionTags),
    };
    final options = selectableRecommendations.take(optionLimit).map((
      recommendation,
    ) {
      final item = recommendation.item;
      final matchedFormats = _matchedRequestedFormats(
        item,
        requestedFormats,
        requireLocalCoOp: requireLocalCoOp,
      );
      final missingFormats = _missingRequestedFormats(
        item,
        requestedFormats,
        requireLocalCoOp: requireLocalCoOp,
      );
      return {
        'id': item.id,
        'title': item.title,
        'score': recommendation.matchScore.round(),
        'tags': item.tags.take(tagLimit).toList(),
        'requestTags': item.tags
            .where(requestTags.contains)
            .take(tagLimit)
            .toList(),
        'format': item.format,
        'requestedFormats': requestedFormats.toList(),
        'matchedFormats': matchedFormats,
        'missingFormats': missingFormats,
        'signals': recommendation.signals.take(signalLimit).toList(),
      };
    }).toList();
    final prompt =
        '''
Pick the single best recommendation for this user from the options.
Prioritize the search request and requestTags first; use user taste and score only to break close ties.
Only the listed options are eligible for this request.
If missingFormats is empty, that option satisfies all requested play modes.
Return JSON only. Use exactly these keys: id, reason. The id must match one option id.
User taste: ${profile.primaryTaste}
Favorite tags: ${profile.favoriteGenres.take(settings.contextItemLimit).join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(signalLimit).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(signalLimit).join(', ')}
Search request: ${query.request}
User-selected tags: ${query.selectedTags.join(', ')}
AI-selected tags: ${query.aiSelectedTags.join(', ')}
Requested formats: ${requestedFormats.join(', ')}
Local co-op required: $requireLocalCoOp
Request-inferred tags: ${query.inferredTags(optionTags).join(', ')}
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
        for (final recommendation in selectableRecommendations) {
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
      if (chosen == null) return selectableRecommendations.first;
      return chosen.copyWith(
        reason: reason == null || reason.isEmpty ? chosen.reason : reason,
        isAiPick: true,
      );
    } catch (_) {
      return fallback.chooseTopRecommendation(
        profile,
        selectableRecommendations,
        query: query,
      );
    }
  }

  @override
  Future<Recommendation?> chooseHomeRecommendation(
    List<TasteProfile> profiles,
    List<Recommendation> recommendations, {
    required RecommendationQuery query,
  }) async {
    if (recommendations.isEmpty) return null;
    final settings = await _runtimeSettings();
    final requestedFormats = query.effectiveFormats();
    final requireLocalCoOp = query.infersLocalCoOp;
    final selectableRecommendations = _formatEligibleRecommendations(
      recommendations,
      requestedFormats,
      requireLocalCoOp: requireLocalCoOp,
    );
    if (!settings.useLocalAi && textGenerator == null) {
      return fallback.chooseHomeRecommendation(
        profiles,
        selectableRecommendations,
        query: query,
      );
    }

    final optionLimit = (settings.contextItemLimit / 4).round().clamp(4, 8);
    final tagLimit = (settings.contextItemLimit / 3).round().clamp(4, 8);
    final profilesSummary = profiles
        .map((profile) => '${profile.serviceName}: ${profile.primaryTaste}')
        .join(' | ');
    final options = selectableRecommendations.take(optionLimit).map((
      recommendation,
    ) {
      final item = recommendation.item;
      return {
        'id': item.id,
        'title': item.title,
        'service': item.serviceLabel,
        'score': recommendation.matchScore.round(),
        'tags': item.tags.take(tagLimit).toList(),
        'format': item.format,
        'requestedFormats': requestedFormats.toList(),
        'matchedFormats': _matchedRequestedFormats(
          item,
          requestedFormats,
          requireLocalCoOp: requireLocalCoOp,
        ),
        'missingFormats': _missingRequestedFormats(
          item,
          requestedFormats,
          requireLocalCoOp: requireLocalCoOp,
        ),
        'mediaType': item.mediaType,
        'reason': recommendation.reason,
      };
    }).toList();
    final prompt =
        '''
Pick the single best next recommendation across all services.
Prioritize the user's search request first. Use service fit, tags, and score to break close ties.
Only the listed options are eligible for this request.
If missingFormats is empty, that option satisfies all requested play modes.
Return JSON only. Use exactly these keys: id, reason. The id must match one option id.
Profiles: $profilesSummary
Search request: ${query.request}
User-selected tags: ${query.selectedTags.join(', ')}
AI-selected tags: ${query.aiSelectedTags.join(', ')}
Requested formats: ${query.formats.join(', ')}
Local co-op required: $requireLocalCoOp
Requested media types: ${query.mediaTypes.join(', ')}
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
        for (final recommendation in selectableRecommendations) {
          if (recommendation.item.id == id) {
            chosen = recommendation;
            reason = candidate['reason']?.toString().trim();
            break;
          }
        }
        if (chosen != null) break;
      }
      if (chosen == null) return selectableRecommendations.first;
      return chosen.copyWith(
        reason: reason == null || reason.isEmpty ? chosen.reason : reason,
        isAiPick: true,
      );
    } catch (_) {
      return fallback.chooseHomeRecommendation(
        profiles,
        recommendations,
        query: query,
      );
    }
  }

  List<Recommendation> _formatEligibleRecommendations(
    List<Recommendation> recommendations,
    Set<String> requestedFormats, {
    required bool requireLocalCoOp,
  }) {
    final eligible = recommendations
        .where(
          (recommendation) => _satisfiesRequestedFormats(
            recommendation.item,
            requestedFormats,
            requireLocalCoOp: requireLocalCoOp,
          ),
        )
        .toList();
    return eligible.isEmpty ? recommendations : eligible;
  }

  bool _satisfiesRequestedFormats(
    MediaItem item,
    Set<String> requestedFormats, {
    required bool requireLocalCoOp,
  }) {
    return _missingRequestedFormats(
      item,
      requestedFormats,
      requireLocalCoOp: requireLocalCoOp,
    ).isEmpty;
  }

  List<String> _matchedRequestedFormats(
    MediaItem item,
    Set<String> requestedFormats, {
    required bool requireLocalCoOp,
  }) {
    return requestedFormats
        .where(
          (format) => _matchesRequestedFormat(
            item,
            format,
            requireLocalCoOp: requireLocalCoOp,
          ),
        )
        .toList();
  }

  List<String> _missingRequestedFormats(
    MediaItem item,
    Set<String> requestedFormats, {
    required bool requireLocalCoOp,
  }) {
    final steamFormats = requestedFormats
        .where(RecommendationQuery.steamFormats.contains)
        .toList();
    final otherFormats = requestedFormats
        .where((format) => !RecommendationQuery.steamFormats.contains(format))
        .toList();
    final missing = <String>[
      for (final format in steamFormats)
        if (!_matchesRequestedFormat(
          item,
          format,
          requireLocalCoOp: requireLocalCoOp,
        ))
          format,
    ];

    if (otherFormats.isNotEmpty &&
        !otherFormats.any(
          (format) => _matchesRequestedFormat(
            item,
            format,
            requireLocalCoOp: requireLocalCoOp,
          ),
        )) {
      missing.addAll(otherFormats);
    }

    return missing;
  }

  bool _matchesRequestedFormat(
    MediaItem item,
    String requestedFormat, {
    required bool requireLocalCoOp,
  }) {
    if (requestedFormat == item.format) return true;
    final normalizedTags = item.tags
        .map((tag) => tag.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ''))
        .toSet();
    if (requestedFormat == 'CO_OP' && requireLocalCoOp) {
      return _localCoOpAliases.any(normalizedTags.contains);
    }
    return _formatAliases(requestedFormat).any(normalizedTags.contains);
  }

  Set<String> get _localCoOpAliases => const {
    'localcoop',
    'localmultiplayer',
    'sharedsplitscreencoop',
    'sharedsplitscreen',
    'splitscreencoop',
    'splitscreen',
    'remoteplaytogether',
    'lancoop',
  };

  Set<String> _formatAliases(String format) {
    return switch (format) {
      'SINGLE_PLAYER' => {'singleplayer'},
      'MULTIPLAYER' => {
        'multiplayer',
        'coop',
        'localcoop',
        'onlinecoop',
        'pvp',
        'onlinepvp',
        'remoteplaytogether',
        'sharedsplitscreencoop',
        'sharedsplitscreenpvp',
      },
      'CO_OP' => {
        'coop',
        'localcoop',
        'sharedsplitscreencoop',
        'remoteplaytogether',
      },
      'ONLINE_CO_OP' => {'onlinecoop'},
      'CONTROLLER' => {
        'controller',
        'controllersupport',
        'fullcontrollersupport',
        'partialcontrollersupport',
      },
      'STEAM_DECK' => {'steamdeck', 'steamdeckverified'},
      _ => {format.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '')},
    };
  }
}
