import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:majika/core/ai/ai_console_log.dart';
import 'package:majika/core/ai/ai_search_tools.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';

final Object localAiConsoleLogZoneKey = Object();
final Object manualAiRequestHandlerZoneKey = Object();

enum _AiPromptTier { compact, balanced, rich }

const _fullPromptLimit = 0x3fffffff;
const _maxAiSelectedTags = 4;

class _PromptLimits {
  final int tagLimit;
  final int optionLimit;
  final int optionTagLimit;
  final int signalLimit;
  final int profileItemLimit;

  const _PromptLimits({
    required this.tagLimit,
    required this.optionLimit,
    required this.optionTagLimit,
    required this.signalLimit,
    required this.profileItemLimit,
  });

  bool get canShrink =>
      tagLimit > 8 ||
      optionLimit > 2 ||
      optionTagLimit > 3 ||
      signalLimit > 2 ||
      profileItemLimit > 3;

  _PromptLimits shrink() {
    int next(int value, int minimum, int firstStep) {
      if (value >= _fullPromptLimit) return firstStep;
      return (value * 0.7).floor().clamp(minimum, value - 1);
    }

    return _PromptLimits(
      tagLimit: next(tagLimit, 8, 512),
      optionLimit: next(optionLimit, 2, 128),
      optionTagLimit: next(optionTagLimit, 3, 32),
      signalLimit: next(signalLimit, 2, 24),
      profileItemLimit: next(profileItemLimit, 3, 128),
    );
  }
}

class _PromptBudget {
  final _AiPromptTier tier;
  final int contextWindowTokens;
  final int responseTokens;
  final int promptTokens;

  const _PromptBudget({
    required this.tier,
    required this.contextWindowTokens,
    required this.responseTokens,
    required this.promptTokens,
  });

  String get instruction =>
      'Token budget: ${formatAiTokenCount(contextWindowTokens)} context, '
      '${formatAiTokenCount(promptTokens)} maximum estimated prompt, '
      '${formatAiTokenCount(responseTokens)} reserved response.';
}

class _PackedPrompt {
  final String prompt;
  final _PromptLimits limits;
  final int estimatedTokens;

  const _PackedPrompt({
    required this.prompt,
    required this.limits,
    required this.estimatedTokens,
  });
}

class _ExternalAiTool {
  final String name;
  final String description;
  final Map<String, Object?> parameters;
  final Future<String> Function(Map<String, dynamic> arguments) execute;

  const _ExternalAiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  Map<String, Object?> toJson() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }
}

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

class AiRecommendationSuggestion {
  final String title;
  final String serviceName;
  final String reason;

  const AiRecommendationSuggestion({
    required this.title,
    required this.serviceName,
    required this.reason,
  });
}

enum AiChatRole { user, assistant, system }

enum AiChatSurface { home, service }

enum AiChatActionType {
  applyQuery,
  runSearch,
  discoverCandidates,
  explainRecommendation,
  backgroundPrompt,
}

class AiChatMessage {
  final AiChatRole role;
  final String text;
  final DateTime timestamp;

  AiChatMessage({required this.role, required this.text, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

class AiChatAction {
  final AiChatActionType type;
  final String label;
  final RecommendationQuery? query;
  final String? recommendationId;
  final String? serviceName;
  final String? prompt;

  const AiChatAction({
    required this.type,
    required this.label,
    this.query,
    this.recommendationId,
    this.serviceName,
    this.prompt,
  });
}

class AiChatRequest {
  final AiChatSurface surface;
  final String serviceName;
  final List<TasteProfile> profiles;
  final RecommendationQuery query;
  final List<Recommendation> recommendations;
  final Map<String, List<Recommendation>> recommendationsByService;
  final List<AiChatMessage> messages;
  final List<String> availableTags;
  final List<String> availableServices;

  const AiChatRequest({
    required this.surface,
    required this.serviceName,
    required this.profiles,
    required this.query,
    required this.recommendations,
    this.recommendationsByService = const {},
    required this.messages,
    this.availableTags = const [],
    this.availableServices = const [],
  });
}

class AiChatResponse {
  final String message;
  final List<AiChatAction> actions;

  const AiChatResponse({required this.message, this.actions = const []});
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

  Future<AiRecommendationSuggestion?> suggestRecommendation(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  });

  Future<List<AiRecommendationSuggestion>> suggestRecommendationCandidates(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
    int limit = 5,
  });

  Future<AiRecommendationSuggestion?> suggestHomeRecommendation(
    List<TasteProfile> profiles,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  });

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

  Future<AiChatResponse> chatAboutRecommendations(AiChatRequest request);
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
  Future<AiRecommendationSuggestion?> suggestRecommendation(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  }) async {
    return null;
  }

  @override
  Future<List<AiRecommendationSuggestion>> suggestRecommendationCandidates(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
    int limit = 5,
  }) async {
    return const [];
  }

  @override
  Future<AiRecommendationSuggestion?> suggestHomeRecommendation(
    List<TasteProfile> profiles,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  }) async {
    return null;
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

  @override
  Future<AiChatResponse> chatAboutRecommendations(AiChatRequest request) async {
    final latestUserMessage = request.messages.reversed
        .where((message) => message.role == AiChatRole.user)
        .map((message) => message.text.trim())
        .firstWhere((message) => message.isNotEmpty, orElse: () => '');
    final topPick = request.recommendations.isEmpty
        ? null
        : request.recommendations.first;
    final profileText = request.profiles.isEmpty
        ? 'your imported taste'
        : request.profiles
              .map(
                (profile) => '${profile.serviceName}: ${profile.primaryTaste}',
              )
              .join(' and ');
    final topText = topPick == null
        ? 'I do not have recommendations on screen yet.'
        : 'The current top pick is ${topPick.item.title}, because ${topPick.reason}';
    final suffix = latestUserMessage.isEmpty
        ? ''
        : ' For "$latestUserMessage", try refining the search text or tags if you want the list to move.';
    return AiChatResponse(message: '$topText I am using $profileText.$suffix');
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
  final AiSearchToolbox searchToolbox;

  const FlutterGemmaLocalAiService({
    this.fallback = const DeterministicLocalAiService(),
    this.textGenerator,
    this.settingsLoader,
    this.httpPost,
    this.searchToolbox = const AiSearchToolbox(),
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

    final budget = _promptBudget(settings, responseTokens: 512);

    try {
      final packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) =>
            _profileSummaryPrompt(profile, limits.profileItemLimit),
      );
      final text = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
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
    final baseSettings = await _runtimeSettings();
    final settings = _effectiveSettingsForTask(
      baseSettings,
      task: 'search_interpretation',
      minimumTier: AiModelTrustTier.constrained,
    );
    final supportsExplicitContent = _isAniListService(serviceName);
    final explicitAllowedBySettings =
        settings.allowExplicitContent && supportsExplicitContent;
    final effectiveQuery = query.copyWith(
      includeAdult: false,
      excludeAdult:
          query.excludeAdult ||
          (supportsExplicitContent && !explicitAllowedBySettings),
    );
    if (!query.isActive ||
        (!settings.useLocalAi && textGenerator == null) ||
        !settings.useAiForSearch) {
      return fallback.interpretRecommendationRequest(
        effectiveQuery,
        availableTags: availableTags,
        serviceName: serviceName,
        allowedMediaTypes: allowedMediaTypes,
        allowedFormats: allowedFormats,
      );
    }

    final budget = _promptBudget(settings, responseTokens: 1024);
    final selectedTagsLine = effectiveQuery.selectedTags.isEmpty
        ? ''
        : 'User-selected tags already active: ${effectiveQuery.selectedTags.join(', ')}\n';
    final selectedFormatsLine = effectiveQuery.formats.isEmpty
        ? ''
        : 'User-selected ${_formatLabel(serviceName)} filters already active: ${effectiveQuery.formats.join(', ')}\n';
    final selectedMediaLine = effectiveQuery.mediaTypes.isEmpty
        ? ''
        : 'User-selected source filters already active: ${effectiveQuery.mediaTypes.join(', ')}\n';
    final adultGuidance = query.excludeAdult
        ? 'Explicit content is hidden by user preference. Set includeAdult to false and do not select adult-only tags.'
        : query.allowsAdult
        ? 'Adult/NSFW content is explicitly requested or enabled for this search; include it only when it improves the requested match.'
        : explicitAllowedBySettings
        ? 'Adult/NSFW content is permitted, but include it only when the request asks for it. Set includeAdult based on the request text.'
        : 'The includeAdult output field means the request explicitly asks for adult/NSFW content; infer it from the request text only.';
    try {
      final packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) => _searchInterpretationPrompt(
          serviceName: serviceName,
          tier: budget.tier,
          query: effectiveQuery,
          allowedMediaTypes: allowedMediaTypes,
          allowedFormats: allowedFormats,
          tagList: _promptTagList(
            query: effectiveQuery,
            availableTags: availableTags,
            serviceName: serviceName,
            limit: limits.tagLimit,
          ).join(', '),
          adultGuidance: adultGuidance,
          selectedTagsLine: selectedTagsLine,
          selectedFormatsLine: selectedFormatsLine,
          selectedMediaLine: selectedMediaLine,
        ),
      );
      final response = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
        settings: settings,
      );
      final interpreted = _queryFromModelJson(
        response,
        original: effectiveQuery,
        availableTags: availableTags,
        allowedMediaTypes: allowedMediaTypes,
        allowedFormats: allowedFormats,
      );
      if (interpreted == null) {
        return fallback.interpretRecommendationRequest(
          effectiveQuery,
          availableTags: availableTags,
          serviceName: serviceName,
          allowedMediaTypes: allowedMediaTypes,
          allowedFormats: allowedFormats,
        );
      }
      return interpreted;
    } catch (_) {
      return fallback.interpretRecommendationRequest(
        effectiveQuery,
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

    final budget = _promptBudget(settings, responseTokens: 384);

    try {
      final packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) => _recommendationExplanationPrompt(
          profile,
          recommendation,
          limits.profileItemLimit,
        ),
      );
      final text = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
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
    List<_ExternalAiTool> externalTools = const [],
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
      try {
        return await _generateExternalText(
          prompt,
          maxTokens: maxTokens,
          settings: settings,
          tools: externalTools,
        );
      } catch (error) {
        log?.addLine('AI request failed: $error');
        rethrow;
      }
    }

    if (!isConfigured) {
      if (settings.hasCloudFallback) {
        _currentConsoleLog?.addLine(
          'No on-device model is configured. Falling back to cloud AI.',
        );
        return _generateExternalText(
          prompt,
          maxTokens: maxTokens,
          settings: settings.asCloudFallback(),
          tools: externalTools,
        );
      }
      throw StateError('No local AI model is configured.');
    }

    final preferredBackend = _safeOnDeviceBackend(settings.preferredBackend);
    try {
      final response = await _generateOnDeviceText(
        prompt,
        contextWindowTokens: settings.contextWindowTokens,
        responseTokens: maxTokens,
        preferredBackend: preferredBackend,
      );
      log?.addSection('Response', response);
      return response;
    } catch (error) {
      log?.addLine('AI request failed: $error');
      if (settings.hasCloudFallback) {
        log?.addLine('Retrying with cloud AI fallback.');
        return _generateExternalText(
          prompt,
          maxTokens: maxTokens,
          settings: settings.asCloudFallback(),
          tools: externalTools,
        );
      }
      if (preferredBackend == null ||
          preferredBackend == PreferredBackend.cpu) {
        rethrow;
      }
      log?.addLine('Retrying on-device AI with CPU backend.');
      final response = await _generateOnDeviceText(
        prompt,
        contextWindowTokens: settings.contextWindowTokens,
        responseTokens: maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );
      log?.addSection('Response', response);
      return response;
    }
  }

  LocalAiRuntimeSettings _effectiveSettingsForTask(
    LocalAiRuntimeSettings settings, {
    required String task,
    required AiModelTrustTier minimumTier,
  }) {
    if (textGenerator != null) return settings;
    final currentTier = _trustTierForTask(settings, task);
    if (_meetsTrustTier(currentTier, minimumTier)) {
      return settings;
    }
    if (!settings.hasCloudFallback) return settings;
    final cloudFallback = settings.asCloudFallback();
    final cloudTier = _trustTierForTask(cloudFallback, task);
    return _meetsTrustTier(cloudTier, minimumTier) ? cloudFallback : settings;
  }

  AiModelTrustTier _trustTierForTask(
    LocalAiRuntimeSettings settings,
    String task,
  ) {
    return switch (task) {
      'search_interpretation' => settings.searchInterpretationTrustTier,
      'steam_discovery' => settings.steamDiscoveryTrustTier,
      'recommendation_selection' => settings.recommendationSelectionTrustTier,
      _ => AiModelTrustTier.unsupported,
    };
  }

  bool _meetsTrustTier(AiModelTrustTier actual, AiModelTrustTier minimum) {
    return actual.index >= minimum.index;
  }

  Future<String> _generateOnDeviceText(
    String prompt, {
    required int contextWindowTokens,
    required int responseTokens,
    required PreferredBackend? preferredBackend,
  }) async {
    final model = await FlutterGemma.getActiveModel(
      maxTokens: contextWindowTokens,
      preferredBackend: preferredBackend,
    );
    try {
      final chat = await model.createChat(
        temperature: 0.1,
        topK: 1,
        tokenBuffer: responseTokens,
        modelType: _activeModelType(),
      );
      final exactPromptTokens = await chat.session.sizeInTokens(prompt);
      if (exactPromptTokens + responseTokens > contextWindowTokens) {
        throw StateError(
          'Prompt requires $exactPromptTokens tokens plus a '
          '$responseTokens-token response reserve, exceeding the '
          '$contextWindowTokens-token model context.',
        );
      }
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
    List<_ExternalAiTool> tools = const [],
  }) async {
    if (tools.isNotEmpty && settings.supportsSearchTools) {
      try {
        return await _generateExternalTextWithTools(
          prompt,
          maxTokens: maxTokens,
          settings: settings,
          tools: tools,
        );
      } catch (error) {
        _currentConsoleLog?.addLine(
          'AI search tools failed, retrying text-only: $error',
        );
      }
    }

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
      final text = _messageTextContent(message['content']);
      if (text.isNotEmpty) {
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

  Future<String> _generateExternalTextWithTools(
    String prompt, {
    required int maxTokens,
    required LocalAiRuntimeSettings settings,
    required List<_ExternalAiTool> tools,
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
    final messages = <Map<String, Object?>>[
      {'role': 'user', 'content': prompt},
    ];
    final toolByName = {for (final tool in tools) tool.name: tool};
    final completedToolPayloads = <String, List<String>>{};

    log?.addLine(
      'Sending tool-enabled request to ${isCloud ? settings.cloudProvider : 'local server'}: $model',
    );

    for (var round = 0; round < 3; round++) {
      final response = await post(
        endpoint,
        headers: headers,
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'tools': [for (final tool in tools) tool.toJson()],
          'tool_choice': 'auto',
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
      final message = _firstChoiceMessage(decoded);
      final toolCalls = _toolCallsFromMessage(message);
      if (toolCalls.isEmpty) {
        final content = _messageTextContent(message['content']);
        if (content.isNotEmpty) {
          log?.addSection('Response', content);
          return content;
        }
        final fallbackText = _firstChoiceText(decoded);
        if (fallbackText.isNotEmpty) {
          log?.addSection('Response', fallbackText);
          return fallbackText;
        }
        throw const FormatException(
          'Tool-enabled AI response did not include text.',
        );
      }

      final names = toolCalls
          .map((call) => call['function']?['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) {
        log?.addLine('AI requested tool(s): $names');
      }
      messages.add({
        'role': 'assistant',
        if (message['content'] != null) 'content': message['content'],
        'tool_calls': toolCalls,
      });

      for (final call in toolCalls) {
        final function = call['function'];
        final name = function?['name']?.toString().trim() ?? '';
        final id = call['id']?.toString().trim() ?? name;
        final tool = toolByName[name];
        final args = _decodeToolArguments(function?['arguments']);
        final result = tool == null
            ? jsonEncode({'error': 'Unknown tool "$name".'})
            : await tool.execute(args);
        if (name.isNotEmpty) {
          log?.addLine('Tool $name completed.');
          completedToolPayloads.putIfAbsent(name, () => []).add(result);
        }
        messages.add({'role': 'tool', 'tool_call_id': id, 'content': result});
      }
    }

    final bestEffort = _bestEffortToolResponse(prompt, completedToolPayloads);
    if (bestEffort != null) {
      log?.addLine('Using best-effort tool result.');
      return bestEffort;
    }

    throw const FormatException(
      'Tool-enabled AI response did not finish within the allowed tool rounds.',
    );
  }

  Map<String, dynamic> _firstChoiceMessage(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Local AI response did not include choices.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw const FormatException('Local AI choice was not a JSON object.');
    }
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException(
        'Local AI response did not include a message.',
      );
    }
    return message;
  }

  String _firstChoiceText(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) return '';
    final text = firstChoice['text'];
    return text?.toString().trim() ?? '';
  }

  List<Map<String, dynamic>> _toolCallsFromMessage(
    Map<String, dynamic> message,
  ) {
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List) return const [];
    return [
      for (final call in toolCalls)
        if (call is Map<String, dynamic>) call,
    ];
  }

  Map<String, dynamic> _decodeToolArguments(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const {};
  }

  String _messageTextContent(Object? content) {
    if (content == null) return '';
    if (content is String) return content.trim();
    if (content is List) {
      final parts = <String>[];
      for (final part in content) {
        if (part is Map<String, dynamic>) {
          final text = part['text']?.toString().trim();
          if (text != null && text.isNotEmpty) parts.add(text);
        } else if (part != null) {
          final text = part.toString().trim();
          if (text.isNotEmpty) parts.add(text);
        }
      }
      return parts.join('\n').trim();
    }
    return content.toString().trim();
  }

  String? _bestEffortToolResponse(
    String prompt,
    Map<String, List<String>> completedToolPayloads,
  ) {
    final steamPayloads =
        completedToolPayloads['search_steam_games'] ?? const [];
    final webPayloads = completedToolPayloads['search_web'] ?? const [];
    final titles = <String>[];

    for (final payload in [...steamPayloads, ...webPayloads]) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) continue;
        final results = decoded['results'];
        if (results is! List) continue;
        for (final entry in results) {
          final title = entry is Map ? entry['title']?.toString().trim() : null;
          if (title != null && title.isNotEmpty && !titles.contains(title)) {
            titles.add(title);
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (titles.isEmpty) return null;
    if (prompt.contains('"titles"')) {
      return jsonEncode({'titles': titles.take(5).toList()});
    }
    return jsonEncode({
      'title': titles.first,
      'reason': 'Chosen from Steam and web search results.',
    });
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
    final formats = {
      ...ruleInterpreted.formats,
      ..._filteredModelFormats(
        original: original,
        allowedFormats: allowedFormats,
        modelFormats: modelFormats,
      ),
    };
    final mediaTypes = {...ruleInterpreted.mediaTypes, ...modelMediaTypes};
    final limitedTags = _limitAiSelectedTags([
      ...ruleInterpreted.aiSelectedTags,
      ...tags,
    ]);

    return original.copyWith(
      interpretedRequest: searchText == null || searchText.isEmpty
          ? ''
          : searchText,
      selectedTags: original.selectedTags,
      aiSelectedTags: limitedTags,
      formats: formats,
      mediaTypes: mediaTypes,
      includeAdult:
          !original.excludeAdult &&
          (ruleInterpreted.includeAdult || decoded['includeAdult'] == true),
      excludeAdult: original.excludeAdult,
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

  Set<String> _limitAiSelectedTags(Iterable<String> tags) {
    final ordered = <String>[];
    for (final tag in tags) {
      if (tag.trim().isEmpty || ordered.contains(tag)) continue;
      ordered.add(tag);
      if (ordered.length >= _maxAiSelectedTags) break;
    }
    return ordered.toSet();
  }

  Set<String> _filteredModelFormats({
    required RecommendationQuery original,
    required Iterable<String> allowedFormats,
    required Set<String> modelFormats,
  }) {
    final allowedSet = allowedFormats.toSet();
    final isSteam = allowedSet.toSet().containsAll(
      RecommendationQuery.steamFormats,
    );
    if (!isSteam) return modelFormats;
    final requestedFormats = original.effectiveFormats();
    return modelFormats.where(requestedFormats.contains).toSet();
  }

  _AiPromptTier _promptTier(LocalAiRuntimeSettings settings) {
    final context = settings.contextWindowTokens;
    if (context <= 8192) return _AiPromptTier.compact;
    if (context <= 32768) return _AiPromptTier.balanced;
    return _AiPromptTier.rich;
  }

  _PromptLimits _promptLimits(_AiPromptTier tier) {
    return switch (tier) {
      _AiPromptTier.compact => const _PromptLimits(
        tagLimit: 18,
        optionLimit: 3,
        optionTagLimit: 5,
        signalLimit: 3,
        profileItemLimit: 4,
      ),
      _AiPromptTier.balanced => const _PromptLimits(
        tagLimit: 80,
        optionLimit: 8,
        optionTagLimit: 10,
        signalLimit: 6,
        profileItemLimit: 10,
      ),
      _AiPromptTier.rich => const _PromptLimits(
        tagLimit: _fullPromptLimit,
        optionLimit: _fullPromptLimit,
        optionTagLimit: _fullPromptLimit,
        signalLimit: _fullPromptLimit,
        profileItemLimit: _fullPromptLimit,
      ),
    };
  }

  _PromptBudget _promptBudget(
    LocalAiRuntimeSettings settings, {
    required int responseTokens,
  }) {
    final context = settings.contextWindowTokens;
    final safeResponse = responseTokens.clamp(256, (context * 0.25).floor());
    final safetyReserve = (context * 0.1).round().clamp(256, 4096);
    return _PromptBudget(
      tier: _promptTier(settings),
      contextWindowTokens: context,
      responseTokens: safeResponse,
      promptTokens: (context - safeResponse - safetyReserve).clamp(
        1024,
        context,
      ),
    );
  }

  int _estimatePromptTokens(String prompt) {
    return (utf8.encode(prompt).length / 3).ceil();
  }

  _PackedPrompt _packPrompt({
    required _PromptBudget budget,
    required _PromptLimits initialLimits,
    required String Function(_PromptLimits limits) build,
  }) {
    var limits = initialLimits;
    var prompt = '${budget.instruction}\n${build(limits)}';
    var estimatedTokens = _estimatePromptTokens(prompt);
    while (estimatedTokens > budget.promptTokens && limits.canShrink) {
      limits = limits.shrink();
      prompt = '${budget.instruction}\n${build(limits)}';
      estimatedTokens = _estimatePromptTokens(prompt);
    }
    if (estimatedTokens > budget.promptTokens) {
      throw StateError(
        'Required AI instructions exceed the configured '
        '${budget.contextWindowTokens}-token context window.',
      );
    }
    return _PackedPrompt(
      prompt: prompt,
      limits: limits,
      estimatedTokens: estimatedTokens,
    );
  }

  String _servicePromptContext(String serviceName) {
    if (_isSteamService(serviceName)) {
      return 'Service context: Steam PC games. Tags are Steam genres, store tags, and play features. Formats are gameplay capability filters such as single-player, co-op, controller, and Steam Deck.';
    }
    if (_isAniListService(serviceName)) {
      return 'Service context: AniList anime and manga. Tags are AniList genres and media tags. Formats are broad content shapes: series, movie, manga, and book.';
    }
    return 'Service context: $serviceName recommendations. Use the service tags and filters below.';
  }

  String _profileSummaryPrompt(TasteProfile profile, int itemLimit) {
    final highRated = profile.highRatedItems
        .map((item) => item.title)
        .take(itemLimit)
        .join(', ');
    if (_isSteamService(profile.serviceName)) {
      final played = profile.library
          .where((item) => (item.playtimeMinutes ?? 0) > 0)
          .take(itemLimit)
          .map((item) => '${item.title} (${item.playtimeMinutes} minutes)')
          .join(', ');
      return '''
Summarize this Steam game taste profile in one concise sentence.
Favorite Steam tags: ${profile.favoriteGenres.join(', ')}
Most-played games: $played
High-rated games: $highRated
''';
    }
    if (_isAniListService(profile.serviceName)) {
      return '''
Summarize this AniList anime and manga taste profile in one concise sentence.
Favorite AniList tags: ${profile.favoriteGenres.join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(itemLimit).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(itemLimit).join(', ')}
High-rated anime or manga: $highRated
''';
    }
    return '''
Summarize this ${profile.serviceName} taste profile in one concise sentence.
Favorite tags: ${profile.favoriteGenres.join(', ')}
High-rated examples: $highRated
''';
  }

  String _recommendationExplanationPrompt(
    TasteProfile profile,
    Recommendation recommendation,
    int itemLimit,
  ) {
    final item = recommendation.item;
    if (_isSteamService(profile.serviceName)) {
      return '''
Explain in one short sentence why this Steam game fits this user's request and game taste. Only use supplied facts.
Game taste: ${profile.primaryTaste}
Favorite Steam tags: ${profile.favoriteGenres.join(', ')}
Recommended game: ${item.title}
Steam tags: ${item.tags.take(itemLimit).join(', ')}
Play capability: ${item.format}
Playtime evidence: ${item.playtimeMinutes ?? 0} total minutes, ${item.recentPlaytimeMinutes ?? 0} recent minutes
Match signals: ${recommendation.signals.take(itemLimit).join(', ')}
''';
    }
    if (_isAniListService(profile.serviceName)) {
      return '''
Explain in one short sentence why this AniList anime or manga title fits this user's request and taste. Only use supplied facts.
Anime and manga taste: ${profile.primaryTaste}
Favorite AniList tags: ${profile.favoriteGenres.join(', ')}
Favorite characters: ${profile.favoriteCharacters.take(itemLimit).join(', ')}
Favorite studios: ${profile.favoriteStudios.take(itemLimit).join(', ')}
Recommended title: ${item.title}
AniList tags: ${item.tags.take(itemLimit).join(', ')}
Release format: ${item.format}
Match signals: ${recommendation.signals.take(itemLimit).join(', ')}
''';
    }
    return '''
Explain in one short sentence why this recommendation fits. Only use supplied facts.
Profile: ${profile.primaryTaste}
Recommendation: ${item.title}
Tags: ${item.tags.take(itemLimit).join(', ')}
Signals: ${recommendation.signals.take(itemLimit).join(', ')}
''';
  }

  String _promptScopeInstruction(_AiPromptTier tier) {
    return switch (tier) {
      _AiPromptTier.compact =>
        'Compact scope: use only the highest-signal evidence supplied and follow the JSON schema exactly.',
      _AiPromptTier.balanced =>
        'Balanced scope: use a broad but bounded selection of profile and candidate evidence.',
      _AiPromptTier.rich =>
        'Full-context scope: all available service tags, eligible candidates, and supplied user-preference evidence are included. Consider the complete evidence before deciding.',
    };
  }

  String _formatLabel(String serviceName) {
    return _isSteamService(serviceName) ? 'play capability' : 'format';
  }

  String _formatInstruction(
    String serviceName,
    Iterable<String> allowedFormats,
  ) {
    final values = allowedFormats.join(', ');
    if (_isSteamService(serviceName)) {
      return 'Steam play capability values for formats: $values';
    }
    if (_isAniListService(serviceName)) {
      return 'AniList release format values for formats: $values';
    }
    return 'Format values: $values';
  }

  String _tagInstruction(String serviceName, _AiPromptTier tier, String tags) {
    final source = _isSteamService(serviceName)
        ? 'Steam'
        : _isAniListService(serviceName)
        ? 'AniList'
        : serviceName;
    final prefix = switch (tier) {
      _AiPromptTier.compact =>
        'High-signal $source tag subset for this small-model prompt',
      _AiPromptTier.balanced => 'Known $source tag subset for this prompt',
      _AiPromptTier.rich => 'Known $source tags fetched for this user/session',
    };
    final catalogGuidance = switch (tier) {
      _AiPromptTier.compact =>
        'Use the listed tags when they clearly match. For obscure official $source tags that are not listed, keep the wording in searchText instead of guessing JSON tags.',
      _AiPromptTier.balanced =>
        'You may output any official $source tag you confidently know, even if this shortened list omits it; Majika validates tags against the service catalog/session tags.',
      _AiPromptTier.rich =>
        'You may output any official $source tag from this fetched catalog/session tag set; keep uncertain or extra wording in searchText.',
    };
    return '$prefix: $tags\n$catalogGuidance\nYou may keep any specific title, franchise, creator, trope, or genre wording that is not in this list in searchText; Majika will use that text to fetch candidates.';
  }

  String _steamToolInstruction(bool allowSearchTools) {
    if (!allowSearchTools) return '';
    return '''
Search tools are available in this runtime.
Use the public web as the primary discovery surface for niche or concept-driven Steam requests, then use Steam search to verify exact Steam titles before deciding.
When the request is niche, skill-based, educational, profession-specific, world-scale, or otherwise likely to miss broad Steam search, call search_web first and search_steam_games second.
Only return titles that you grounded through web evidence and that should be searchable on Steam.
''';
  }

  List<_ExternalAiTool> _steamExternalTools() {
    return [
      _ExternalAiTool(
        name: 'search_steam_games',
        description:
            'Search Steam store games by natural-language query and return exact Steam titles with snippets and tags.',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The Steam game search query.',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of Steam results to return.',
            },
          },
          'required': ['query'],
        },
        execute: (arguments) async {
          final query = arguments['query']?.toString().trim() ?? '';
          final limit = (arguments['limit'] as num?)?.toInt() ?? 5;
          final results = await searchToolbox.searchSteamGames(
            query,
            limit: limit,
          );
          return jsonEncode({'results': results});
        },
      ),
      _ExternalAiTool(
        name: 'search_web',
        description:
            'Search the public web for grounded references such as recommendation lists, exact game names, or descriptions.',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The public web search query.',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of web results to return.',
            },
          },
          'required': ['query'],
        },
        execute: (arguments) async {
          final query = arguments['query']?.toString().trim() ?? '';
          final limit = (arguments['limit'] as num?)?.toInt() ?? 5;
          final results = await searchToolbox.searchWeb(query, limit: limit);
          return jsonEncode({'results': results});
        },
      ),
    ];
  }

  String _searchInterpretationPrompt({
    required String serviceName,
    required _AiPromptTier tier,
    required RecommendationQuery query,
    required Iterable<String> allowedMediaTypes,
    required Iterable<String> allowedFormats,
    required String tagList,
    required String adultGuidance,
    required String selectedTagsLine,
    required String selectedFormatsLine,
    required String selectedMediaLine,
  }) {
    if (_isSteamService(serviceName)) {
      return _steamSearchInterpretationPrompt(
        tier: tier,
        query: query,
        allowedFormats: allowedFormats,
        tagList: tagList,
        selectedTagsLine: selectedTagsLine,
        selectedFormatsLine: selectedFormatsLine,
      );
    }
    if (_isAniListService(serviceName)) {
      return _aniListSearchInterpretationPrompt(
        tier: tier,
        query: query,
        allowedMediaTypes: allowedMediaTypes,
        allowedFormats: allowedFormats,
        tagList: tagList,
        adultGuidance: adultGuidance,
        selectedTagsLine: selectedTagsLine,
        selectedFormatsLine: selectedFormatsLine,
        selectedMediaLine: selectedMediaLine,
      );
    }
    return _genericSearchInterpretationPrompt(
      serviceName: serviceName,
      tier: tier,
      query: query,
      allowedMediaTypes: allowedMediaTypes,
      allowedFormats: allowedFormats,
      tagList: tagList,
      adultGuidance: adultGuidance,
      selectedTagsLine: selectedTagsLine,
      selectedFormatsLine: selectedFormatsLine,
      selectedMediaLine: selectedMediaLine,
    );
  }

  String _steamSearchInterpretationPrompt({
    required _AiPromptTier tier,
    required RecommendationQuery query,
    required Iterable<String> allowedFormats,
    required String tagList,
    required String selectedTagsLine,
    required String selectedFormatsLine,
  }) {
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext('Steam')}
You turn a Steam game request into Steam store-search help for Majika.
This is not the final recommendation prompt. Preserve game titles, franchises, developers, unusual mechanics, and specific taste words in searchText so Majika can fetch candidates beyond tag matches. A later AI prompt will personally pick the best game.
Return JSON only. No markdown. No explanation.
Return one object with exactly these keys: tags, formats, searchText.
The formats field is Majika's transport field for Steam play capabilities only.
Use empty arrays when no known Steam tag or play capability clearly matches.
Return at most $_maxAiSelectedTags tags, ordered from strongest to weakest signal.
Only return play capabilities the user explicitly asked for or that are already active. Do not add Controller or Steam Deck unless the request actually says that.
For adult/sexual Steam requests, use Steam tags such as Sexual Content, Nudity, Mature, NSFW, Hentai, Dating Sim, or Visual Novel when they clearly match.
Do not return AniList media types, AniList release formats, or adult-content fields.
Keep leftover natural-language game terms in searchText.
Keep searchText short and close to the user's wording. Do not rewrite the whole request.
For niche Steam requests about a specific job, machine, object, profession, or activity, prefer searchText over broad tags. Leave tags empty unless an exact Steam tag adds real precision.
${_formatInstruction('Steam', allowedFormats)}
${_tagInstruction('Steam', tier, tagList)}
User request: ${query.request}
$selectedTagsLine$selectedFormatsLine
''';
  }

  String _aniListSearchInterpretationPrompt({
    required _AiPromptTier tier,
    required RecommendationQuery query,
    required Iterable<String> allowedMediaTypes,
    required Iterable<String> allowedFormats,
    required String tagList,
    required String adultGuidance,
    required String selectedTagsLine,
    required String selectedFormatsLine,
    required String selectedMediaLine,
  }) {
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext('AniList')}
You turn an anime or manga request into AniList search help for Majika.
This is not the final recommendation prompt. Preserve titles, franchises, creators, unusual tropes, and specific taste words in searchText so Majika can fetch candidates beyond tag matches. A later AI prompt will personally pick the best title.
Return JSON only. No markdown. No explanation.
Return one object with exactly these keys: tags, formats, mediaTypes, includeAdult, searchText.
Use empty arrays when no known AniList tag, broad format, or media type clearly matches.
Return at most $_maxAiSelectedTags tags, ordered from strongest to weakest signal.
Do not return Steam store tags or Steam play capabilities.
Keep leftover natural-language anime or manga terms in searchText.
Keep searchText short and close to the user's wording. Do not rewrite the whole request.
AniList media type values: ${allowedMediaTypes.join(', ')}
${_formatInstruction('AniList', allowedFormats)}
${_tagInstruction('AniList', tier, tagList)}
$adultGuidance
User request: ${query.request}
$selectedTagsLine$selectedFormatsLine$selectedMediaLine
''';
  }

  String _genericSearchInterpretationPrompt({
    required String serviceName,
    required _AiPromptTier tier,
    required RecommendationQuery query,
    required Iterable<String> allowedMediaTypes,
    required Iterable<String> allowedFormats,
    required String tagList,
    required String adultGuidance,
    required String selectedTagsLine,
    required String selectedFormatsLine,
    required String selectedMediaLine,
  }) {
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext(serviceName)}
You turn recommendation search text into structured search help for Majika.
This is not the final recommendation prompt. Preserve titles, franchise names, and unusual taste words in searchText so Majika can fetch candidates beyond tag matches. A later AI prompt will personally pick the best candidate.
Return JSON only. No markdown. No explanation.
Return one object with exactly these keys: tags, formats, mediaTypes, includeAdult, searchText.
Use empty arrays when no known tag, ${_formatLabel(serviceName)}, or source type clearly matches.
Return at most $_maxAiSelectedTags tags, ordered from strongest to weakest signal.
Keep leftover natural-language terms in searchText.
Keep searchText short and close to the user's wording. Do not rewrite the whole request.
Service source values: ${allowedMediaTypes.join(', ')}
${_formatInstruction(serviceName, allowedFormats)}
${_tagInstruction(serviceName, tier, tagList)}
$adultGuidance
User request: ${query.request}
$selectedTagsLine$selectedFormatsLine$selectedMediaLine
''';
  }

  bool _isSteamService(String serviceName) {
    return serviceName.toLowerCase().contains('steam');
  }

  bool _isAniListService(String serviceName) {
    final normalized = serviceName.toLowerCase();
    return normalized.contains('anilist') ||
        normalized.contains('anime') ||
        normalized.contains('manga');
  }

  List<String> _serviceFallbackTags(String serviceName) {
    if (_isSteamService(serviceName)) {
      return RecommendationQuery.steamBrowsableTags;
    }
    if (_isAniListService(serviceName)) {
      return RecommendationQuery.aniListBrowsableTags;
    }
    return const [];
  }

  List<String> _promptTagList({
    required RecommendationQuery query,
    required Iterable<String> availableTags,
    required String serviceName,
    required int limit,
  }) {
    final serviceTags = [
      ...availableTags.where((tag) => tag.trim().isNotEmpty),
      if (!availableTags.any((tag) => tag.trim().isNotEmpty))
        ..._serviceFallbackTags(serviceName),
    ];
    final tags = <String>{
      ...query.selectedTags,
      ...query.inferredTags(serviceTags),
      for (final tag in serviceTags)
        if (_tagLooksRequested(query.request, tag)) tag,
    };

    for (final tag in serviceTags) {
      if (tags.length >= limit) break;
      tags.add(tag);
    }

    return tags.take(limit).toList();
  }

  bool _tagLooksRequested(String request, String tag) {
    final normalizedRequest = _canonicalKey(request);
    if (normalizedRequest.isEmpty) return false;
    final normalizedTag = _canonicalKey(tag);
    return normalizedTag.isNotEmpty &&
        normalizedRequest.contains(normalizedTag);
  }

  String _profilePromptEvidence(
    TasteProfile profile,
    _AiPromptTier tier,
    _PromptLimits limits,
  ) {
    if (tier == _AiPromptTier.compact) {
      return '''
User taste: ${profile.primaryTaste}
Favorite tags: ${profile.favoriteGenres.take(limits.profileItemLimit).join(', ')}
''';
    }

    final isSteam = _isSteamService(profile.serviceName);
    final evidence = {
      'service': profile.serviceName,
      'summary': profile.summary,
      if (isSteam) ...{
        'favoriteSteamTags': profile.favoriteGenres
            .take(limits.profileItemLimit)
            .toList(),
        'steamTagWeights': _topEntries(
          profile.tagWeights,
          limits.profileItemLimit,
        ),
        'playCapabilityWeights': _topEntries(
          profile.formatWeights,
          limits.profileItemLimit,
        ),
        'playCapabilityCounts': profile.formatCounts,
      } else ...{
        'favoriteAniListTags': profile.favoriteGenres
            .take(limits.profileItemLimit)
            .toList(),
        'aniListTagWeights': _topEntries(
          profile.tagWeights,
          limits.profileItemLimit,
        ),
        'releaseFormatWeights': _topEntries(
          profile.formatWeights,
          limits.profileItemLimit,
        ),
        'releaseFormatCounts': profile.formatCounts,
      },
      'completedCount': profile.completedCount,
      'currentCount': profile.currentCount,
      'highRated': profile.highRatedItems
          .take(limits.profileItemLimit)
          .map((item) => _mediaEvidence(item, serviceName: profile.serviceName))
          .toList(),
      'recentActivity': profile.recentActivity == null
          ? null
          : _mediaEvidence(
              profile.recentActivity!,
              serviceName: profile.serviceName,
            ),
      if (tier == _AiPromptTier.rich)
        'librarySample': profile.library
            .take(limits.profileItemLimit)
            .map(
              (item) => _mediaEvidence(item, serviceName: profile.serviceName),
            )
            .toList(),
      if (!isSteam) ...{
        'favoriteCharacters': profile.favoriteCharacters
            .take(limits.profileItemLimit)
            .toList(),
        'favoriteStaff': profile.favoriteStaff
            .take(limits.profileItemLimit)
            .toList(),
        'favoriteStudios': profile.favoriteStudios
            .take(limits.profileItemLimit)
            .toList(),
      },
    };

    return 'User profile evidence: ${jsonEncode(evidence)}';
  }

  List<Map<String, Object>> _topEntries(Map<String, double> values, int limit) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries.take(limit))
        {'name': entry.key, 'weight': entry.value},
    ];
  }

  Map<String, Object?> _mediaEvidence(
    MediaItem item, {
    required String serviceName,
  }) {
    final common = <String, Object?>{
      'title': item.title,
      'service': item.serviceLabel,
      'rating': item.rating,
      'description': item.description,
    };
    if (_isSteamService(serviceName)) {
      return {
        ...common,
        'steamTags': item.tags,
        'playCapability': item.format,
        'playtimeMinutes': item.playtimeMinutes,
        'recentPlaytimeMinutes': item.recentPlaytimeMinutes,
      };
    }
    if (_isAniListService(serviceName)) {
      return {
        ...common,
        'aniListTags': item.tags,
        'releaseFormat': item.format,
        'mediaType': item.mediaType,
        'status': item.status,
        'startYear': item.startYear,
        'popularity': item.popularity,
        'isAdult': item.isAdult,
        'characters': item.characters,
        'studios': item.studios,
      };
    }
    return {
      ...common,
      'tags': item.tags,
      'format': item.format,
      'mediaType': item.mediaType,
      'status': item.status,
      'startYear': item.startYear,
      'popularity': item.popularity,
      'isAdult': item.isAdult,
      'playtimeMinutes': item.playtimeMinutes,
      'recentPlaytimeMinutes': item.recentPlaytimeMinutes,
      'characters': item.characters,
      'studios': item.studios,
    };
  }

  String _recommendationChatPrompt({
    required AiChatRequest request,
    required _AiPromptTier tier,
    required _PromptLimits limits,
    required bool allowExplicitContent,
  }) {
    final messageLimit = switch (tier) {
      _AiPromptTier.compact => 4,
      _AiPromptTier.balanced => 8,
      _AiPromptTier.rich => 14,
    };
    final optionLimit = switch (tier) {
      _AiPromptTier.compact => 3,
      _AiPromptTier.balanced => 8,
      _AiPromptTier.rich => 18,
    };
    final history = request.messages
        .skip(max(0, request.messages.length - messageLimit))
        .map((message) => {'role': message.role.name, 'text': message.text})
        .toList();
    final profileEvidence = request.profiles
        .take(tier == _AiPromptTier.compact ? 1 : request.profiles.length)
        .map((profile) => _profilePromptEvidence(profile, tier, limits))
        .join('\n');
    final recommendations = request.recommendations
        .take(optionLimit)
        .map(
          (recommendation) => _chatRecommendationEvidence(
            recommendation,
            tier: tier,
            tagLimit: limits.optionTagLimit,
            signalLimit: limits.signalLimit,
          ),
        )
        .toList();
    final byService = {
      for (final entry in request.recommendationsByService.entries)
        entry.key: entry.value
            .take(tier == _AiPromptTier.compact ? 3 : optionLimit)
            .map(
              (recommendation) => _chatRecommendationEvidence(
                recommendation,
                tier: tier,
                tagLimit: limits.optionTagLimit,
                signalLimit: limits.signalLimit,
              ),
            )
            .toList(),
    };
    final availableTags = request.availableTags.take(limits.tagLimit).toList();
    final explicitGuidance = allowExplicitContent
        ? 'Explicit/adult content may be discussed, but only request it when the user asks.'
        : 'Explicit/adult content is hidden. Do not suggest adult tags, adult searches, or adult candidate discovery actions.';

    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
You are Majika's contextual recommendation chat.
Answer the user's latest message about the current recommendations, taste profile, filters, and available services.
You may propose safe actions, but actions are suggestions for Majika to validate and execute through its own APIs. Do not claim an action already happened.
Allowed action types: applyQuery, runSearch, discoverCandidates, explainRecommendation, backgroundPrompt.
Use applyQuery when the user might want to inspect a refined search before running it.
Use runSearch only when the user clearly asks to search or change the list now.
Use discoverCandidates when the current list seems too shallow and the user asks for fresh or outside-the-list ideas.
Use explainRecommendation with a recommendationId from the supplied recommendations.
Use backgroundPrompt for longer comparison or summary work that can finish separately.
$explicitGuidance
Return JSON only. Use exactly this shape: {"message":"short helpful response","actions":[{"type":"runSearch","label":"Run search","query":{"request":"...","tags":[],"formats":[],"mediaTypes":[],"includeAdult":false}},{"type":"explainRecommendation","label":"Explain top pick","recommendationId":"..."}]}.
The query object may use these keys: request, tags, formats, mediaTypes, includeAdult. Keep labels short.
Active surface: ${request.surface.name}
Active service: ${request.serviceName}
Available services: ${request.availableServices.join(', ')}
Current query: ${jsonEncode(request.query.toJson())}
Available tags: ${jsonEncode(availableTags)}
$profileEvidence
Current recommendations: ${jsonEncode(recommendations)}
Recommendations by service: ${jsonEncode(byService)}
Recent chat messages: ${jsonEncode(history)}
''';
  }

  Map<String, Object?> _chatRecommendationEvidence(
    Recommendation recommendation, {
    required _AiPromptTier tier,
    required int tagLimit,
    required int signalLimit,
  }) {
    final item = recommendation.item;
    return {
      'id': item.id,
      'title': item.title,
      'service': item.serviceLabel,
      'score': recommendation.matchScore.round(),
      'reason': recommendation.reason,
      'signals': recommendation.signals.take(signalLimit).toList(),
      'tags': item.tags.take(tagLimit).toList(),
      'mediaType': item.mediaType,
      'format': item.format,
      if (tier != _AiPromptTier.compact) ...{
        'subtitle': item.subtitle,
        'description': item.description,
        'rating': item.rating,
      },
      if (tier == _AiPromptTier.rich) ...{
        'status': item.status,
        'startYear': item.startYear,
        'popularity': item.popularity,
        'playtimeMinutes': item.playtimeMinutes,
        'recentPlaytimeMinutes': item.recentPlaytimeMinutes,
        'characters': item.characters,
        'studios': item.studios,
      },
    };
  }

  AiChatResponse? _chatResponseFromModelJson(
    String response, {
    required RecommendationQuery originalQuery,
    required Iterable<String> availableTags,
    required bool allowExplicitContent,
  }) {
    Map<String, dynamic>? decoded;
    for (final candidate in _jsonObjects(response)) {
      if (candidate.containsKey('message') ||
          candidate.containsKey('actions')) {
        decoded = candidate;
      }
    }
    if (decoded == null) return null;

    final message = decoded['message']?.toString().trim() ?? '';
    final rawActions = decoded['actions'];
    final actions = <AiChatAction>[];
    if (rawActions is List) {
      for (final rawAction in rawActions) {
        if (rawAction is Map) {
          final parsed = _chatActionFromJson(
            Map<String, dynamic>.from(rawAction),
            originalQuery: originalQuery,
            availableTags: availableTags,
            allowExplicitContent: allowExplicitContent,
          );
          if (parsed != null) actions.add(parsed);
        }
      }
    }

    if (message.isEmpty && actions.isEmpty) return null;
    return AiChatResponse(
      message: message.isEmpty ? 'I found a possible next step.' : message,
      actions: actions,
    );
  }

  AiChatAction? _chatActionFromJson(
    Map<String, dynamic> json, {
    required RecommendationQuery originalQuery,
    required Iterable<String> availableTags,
    required bool allowExplicitContent,
  }) {
    final type = switch (json['type']?.toString().trim()) {
      'applyQuery' => AiChatActionType.applyQuery,
      'runSearch' => AiChatActionType.runSearch,
      'discoverCandidates' => AiChatActionType.discoverCandidates,
      'explainRecommendation' => AiChatActionType.explainRecommendation,
      'backgroundPrompt' => AiChatActionType.backgroundPrompt,
      _ => null,
    };
    if (type == null) return null;
    final label = json['label']?.toString().trim();
    final query = json['query'] is Map
        ? _chatQueryFromJson(
            Map<String, dynamic>.from(json['query'] as Map),
            originalQuery: originalQuery,
            availableTags: availableTags,
            allowExplicitContent: allowExplicitContent,
          )
        : null;
    final recommendationId =
        json['recommendationId']?.toString().trim() ??
        json['id']?.toString().trim();
    final prompt = json['prompt']?.toString().trim();
    final serviceName = json['service']?.toString().trim();

    if ((type == AiChatActionType.applyQuery ||
            type == AiChatActionType.runSearch ||
            type == AiChatActionType.discoverCandidates) &&
        query == null) {
      return null;
    }
    if (type == AiChatActionType.explainRecommendation &&
        (recommendationId == null || recommendationId.isEmpty)) {
      return null;
    }
    if (type == AiChatActionType.backgroundPrompt &&
        (prompt == null || prompt.isEmpty)) {
      return null;
    }

    return AiChatAction(
      type: type,
      label: label == null || label.isEmpty
          ? _defaultChatActionLabel(type)
          : label,
      query: query,
      recommendationId: recommendationId,
      serviceName: serviceName == null || serviceName.isEmpty
          ? null
          : serviceName,
      prompt: prompt,
    );
  }

  RecommendationQuery _chatQueryFromJson(
    Map<String, dynamic> json, {
    required RecommendationQuery originalQuery,
    required Iterable<String> availableTags,
    required bool allowExplicitContent,
  }) {
    final availableTagSet = _canonicalLookup(availableTags);
    final tags = _stringList(json['tags'])
        .map((tag) => availableTagSet[_canonicalKey(tag)])
        .whereType<String>()
        .where((tag) => allowExplicitContent || !_adultTagNames.contains(tag))
        .toSet();
    final formats = _stringList(json['formats'])
        .map(RecommendationQuery.canonicalFormat)
        .where((format) => RecommendationQuery.allFormats.contains(format))
        .toSet();
    final mediaTypes = _stringList(json['mediaTypes'])
        .map((type) => type.toUpperCase())
        .where((type) => RecommendationQuery.allMediaTypes.contains(type))
        .toSet();
    final includeAdult = allowExplicitContent && json['includeAdult'] == true;
    final requestText = json['request']?.toString().trim();
    return originalQuery.copyWith(
      request: requestText == null || requestText.isEmpty
          ? originalQuery.request
          : requestText,
      aiSelectedTags: tags,
      formats: formats,
      mediaTypes: mediaTypes,
      includeAdult: includeAdult,
      excludeAdult: originalQuery.excludeAdult || !allowExplicitContent,
    );
  }

  String _defaultChatActionLabel(AiChatActionType type) {
    return switch (type) {
      AiChatActionType.applyQuery => 'Apply search',
      AiChatActionType.runSearch => 'Run search',
      AiChatActionType.discoverCandidates => 'Find candidates',
      AiChatActionType.explainRecommendation => 'Explain pick',
      AiChatActionType.backgroundPrompt => 'Think more',
    };
  }

  static const Set<String> _adultTagNames = {
    'Ecchi',
    'Hentai',
    'Sexual Content',
    'Nudity',
    'Mature',
    'NSFW',
  };

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

  Map<String, Object?> _serviceTopOptionEvidence({
    required String serviceName,
    required Recommendation recommendation,
    required _AiPromptTier tier,
    required Set<String> requestedFormats,
    required bool requireLocalCoOp,
    required Set<String> requestTags,
    required RecommendationQuery query,
    required int tagLimit,
    required int signalLimit,
  }) {
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
    final matchedRequestTags = item.tags
        .where(requestTags.contains)
        .take(tagLimit)
        .toList();
    final common = <String, Object?>{
      'id': item.id,
      'title': item.title,
      'score': recommendation.matchScore.round(),
      'signals': recommendation.signals.take(signalLimit).toList(),
      if (tier != _AiPromptTier.compact) ...{
        'rating': item.rating,
        'description': item.description,
        'reasonFromRanker': recommendation.reason,
      },
    };
    final requestFit = _requestFitEvidence(
      item,
      query: query,
      requestTags: requestTags,
    );
    if (_isSteamService(serviceName)) {
      return {
        ...common,
        'steamTags': item.tags.take(tagLimit).toList(),
        'matchedRequestSteamTags': matchedRequestTags,
        'requestFitEvidence': requestFit,
        'playCapability': item.format,
        'requestedPlayCapabilities': requestedFormats.toList(),
        'matchedPlayCapabilities': matchedFormats,
        'missingPlayCapabilities': missingFormats,
        if (tier == _AiPromptTier.rich) ...{
          'playtimeMinutes': item.playtimeMinutes,
          'recentPlaytimeMinutes': item.recentPlaytimeMinutes,
        },
      };
    }
    if (_isAniListService(serviceName)) {
      return {
        ...common,
        'aniListTags': item.tags.take(tagLimit).toList(),
        'matchedRequestAniListTags': matchedRequestTags,
        'requestFitEvidence': requestFit,
        'releaseFormat': item.format,
        'requestedReleaseFormats': requestedFormats.toList(),
        'matchedReleaseFormats': matchedFormats,
        'missingReleaseFormats': missingFormats,
        if (tier != _AiPromptTier.compact) 'mediaType': item.mediaType,
        if (tier == _AiPromptTier.rich) ...{
          'status': item.status,
          'startYear': item.startYear,
          'popularity': item.popularity,
          'isAdult': item.isAdult,
          'characters': item.characters,
          'studios': item.studios,
        },
      };
    }
    return {
      ...common,
      'tags': item.tags.take(tagLimit).toList(),
      'requestTags': matchedRequestTags,
      'requestFitEvidence': requestFit,
      'format': item.format,
      'requestedFormats': requestedFormats.toList(),
      'matchedFormats': matchedFormats,
      'missingFormats': missingFormats,
      if (tier != _AiPromptTier.compact) 'mediaType': item.mediaType,
    };
  }

  String _serviceTopRecommendationPrompt({
    required TasteProfile profile,
    required _AiPromptTier tier,
    required _PromptLimits limits,
    required RecommendationQuery query,
    required Set<String> requestedFormats,
    required bool requireLocalCoOp,
    required Iterable<String> inferredTags,
    required List<Map<String, Object?>> options,
  }) {
    if (_isSteamService(profile.serviceName)) {
      return _steamTopRecommendationPrompt(
        profile: profile,
        tier: tier,
        limits: limits,
        query: query,
        requestedFormats: requestedFormats,
        requireLocalCoOp: requireLocalCoOp,
        inferredTags: inferredTags,
        options: options,
      );
    }
    if (_isAniListService(profile.serviceName)) {
      return _aniListTopRecommendationPrompt(
        profile: profile,
        tier: tier,
        limits: limits,
        query: query,
        requestedFormats: requestedFormats,
        inferredTags: inferredTags,
        options: options,
      );
    }
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext(profile.serviceName)}
Pick the single best recommendation for this user from the options.
Treat tags, requestTags, scores, and ranker reasons as evidence, not as the decision itself.
First filter for the strongest match to the user's request. Use the taste profile only as secondary guidance or a tie-breaker.
Prioritize the user's request before personal taste. A lower-score option can win when it better matches the request.
Write the reason around why the chosen option fits the request; mention personal taste only when it adds useful context.
Only the listed options are eligible for this request.
Return JSON only. Use exactly these keys: id, reason. The id must match one option id. Keep reason to one short sentence under 25 words.
${_profilePromptEvidence(profile, tier, limits)}
Search request: ${query.request}
User-selected tags: ${query.selectedTags.join(', ')}
Requested formats: ${requestedFormats.join(', ')}
Request-inferred tags: ${inferredTags.join(', ')}
Options: ${jsonEncode(options)}
''';
  }

  String _steamTopRecommendationPrompt({
    required TasteProfile profile,
    required _AiPromptTier tier,
    required _PromptLimits limits,
    required RecommendationQuery query,
    required Set<String> requestedFormats,
    required bool requireLocalCoOp,
    required Iterable<String> inferredTags,
    required List<Map<String, Object?>> options,
  }) {
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext('Steam')}
Pick the single best Steam game for this user from the Steam game options.
Treat Steam store tags, matchedRequestSteamTags, scores, playtime, and ranker reasons as evidence, not as the decision itself.
First filter for the strongest match to the game request. Use the user's Steam taste profile only as secondary guidance or a tie-breaker.
Prioritize the user's request before personal taste. A lower-score option can win when it better matches the request.
Do not pick a broadly popular or profile-shaped game when another option better satisfies the requested mood, mechanic, theme, tag, franchise, format, or play capability.
Write the reason around why the chosen game fits the request; mention personal taste only when it adds useful context.
Only the listed Steam game options are eligible for this request.
If missingPlayCapabilities is empty, that game satisfies every required Steam play capability.
Return JSON only. Use exactly these keys: id, reason. The id must match one option id. Keep reason to one short sentence under 25 words.
${_profilePromptEvidence(profile, tier, limits)}
Game request: ${query.request}
User-selected Steam tags: ${query.selectedTags.join(', ')}
AI-selected Steam tags: ${query.aiSelectedTags.join(', ')}
Required Steam play capabilities: ${requestedFormats.join(', ')}
Local co-op required: $requireLocalCoOp
Text-inferred Steam tags: ${inferredTags.join(', ')}
Steam game options: ${jsonEncode(options)}
''';
  }

  String _aniListTopRecommendationPrompt({
    required TasteProfile profile,
    required _AiPromptTier tier,
    required _PromptLimits limits,
    required RecommendationQuery query,
    required Set<String> requestedFormats,
    required Iterable<String> inferredTags,
    required List<Map<String, Object?>> options,
  }) {
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext('AniList')}
Pick the single best AniList anime or manga recommendation for this user from the AniList options.
Treat AniList tags, matchedRequestAniListTags, scores, staff, studios, and ranker reasons as evidence, not as the decision itself.
First filter for the strongest match to the user's request. Use the anime/manga taste profile only as secondary guidance or a tie-breaker.
Prioritize the user's request before personal taste. A lower-score option can win when it better matches the request.
Write the reason around why the chosen title fits the request; mention personal taste only when it adds useful context.
Only the listed AniList options are eligible for this request.
If missingReleaseFormats is empty, that title satisfies the requested AniList release-format constraint.
Return JSON only. Use exactly these keys: id, reason. The id must match one option id. Keep reason to one short sentence under 25 words.
${_profilePromptEvidence(profile, tier, limits)}
Anime or manga request: ${query.request}
User-selected AniList tags: ${query.selectedTags.join(', ')}
Requested AniList release formats: ${requestedFormats.join(', ')}
Requested AniList media types: ${query.mediaTypes.join(', ')}
Request-inferred AniList tags: ${inferredTags.join(', ')}
AniList options: ${jsonEncode(options)}
''';
  }

  Map<String, Object?> _homeOptionEvidence({
    required Recommendation recommendation,
    required _AiPromptTier tier,
    required Set<String> requestedFormats,
    required bool requireLocalCoOp,
    required int tagLimit,
  }) {
    final item = recommendation.item;
    final common = <String, Object?>{
      'id': item.id,
      'title': item.title,
      'service': item.serviceLabel,
      'score': recommendation.matchScore.round(),
      'requestedConstraints': requestedFormats.toList(),
      'matchedConstraints': _matchedRequestedFormats(
        item,
        requestedFormats,
        requireLocalCoOp: requireLocalCoOp,
      ),
      'missingConstraints': _missingRequestedFormats(
        item,
        requestedFormats,
        requireLocalCoOp: requireLocalCoOp,
      ),
      'reasonFromRanker': recommendation.reason,
      if (tier != _AiPromptTier.compact) ...{
        'rating': item.rating,
        'description': item.description,
      },
      if (tier == _AiPromptTier.rich) 'signals': recommendation.signals,
    };
    if (_isSteamService(item.serviceLabel)) {
      return {
        ...common,
        'steamTags': item.tags.take(tagLimit).toList(),
        'playCapability': item.format,
        if (tier == _AiPromptTier.rich) ...{
          'playtimeMinutes': item.playtimeMinutes,
          'recentPlaytimeMinutes': item.recentPlaytimeMinutes,
        },
      };
    }
    if (_isAniListService(item.serviceLabel)) {
      return {
        ...common,
        'aniListTags': item.tags.take(tagLimit).toList(),
        'releaseFormat': item.format,
        'mediaType': item.mediaType,
        if (tier == _AiPromptTier.rich) ...{
          'status': item.status,
          'startYear': item.startYear,
          'popularity': item.popularity,
          'isAdult': item.isAdult,
          'characters': item.characters,
          'studios': item.studios,
        },
      };
    }
    return {
      ...common,
      'tags': item.tags.take(tagLimit).toList(),
      'format': item.format,
      'mediaType': item.mediaType,
    };
  }

  List<Map<String, Object?>> _directPickHints(
    Iterable<Recommendation> recommendations,
    int limit,
  ) {
    return [
      for (final recommendation in recommendations.take(limit))
        {
          'title': recommendation.item.title,
          'service': recommendation.item.serviceLabel,
          'mediaType': recommendation.item.mediaType,
          'format': recommendation.item.format,
        },
    ];
  }

  String _adultRecommendationGuidance(
    RecommendationQuery query, {
    required bool supportsAdultContent,
  }) {
    if (!supportsAdultContent) return '';
    if (query.excludeAdult) {
      return 'Explicit content is hidden by user preference. Never choose an adult-only title, even when the request asks for one.';
    }
    if (query.allowsAdult) {
      return 'Adult titles are allowed for this request. Consider them normally when they are the best fit.';
    }
    return 'Do not choose an adult-only title unless the request explicitly asks for one.';
  }

  List<String> _requestFitEvidence(
    MediaItem item, {
    required RecommendationQuery query,
    required Set<String> requestTags,
  }) {
    final evidence = <String>[];
    final itemTags = item.tags.map(_canonicalKey).toSet();
    for (final tag in requestTags) {
      if (itemTags.contains(_canonicalKey(tag))) {
        evidence.add('tag:$tag');
      }
    }

    final text = '${item.title} ${item.description ?? ''}'.toLowerCase();
    for (final phrase in _requestIntentPhrases(query)) {
      if (text.contains(phrase)) {
        evidence.add('text:$phrase');
      }
    }

    return _uniqueStrings(evidence).take(8).toList();
  }

  List<String> _requestIntentPhrases(RecommendationQuery query) {
    final phrases = <String>[
      ...query.selectedTags,
      ...query.aiSelectedTags,
      ...query.request
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9+]+'))
          .where((word) => word.length >= 4),
    ];
    return _uniqueStrings(
      phrases
          .map((phrase) => phrase.toLowerCase().trim())
          .where((phrase) => phrase.isNotEmpty)
          .where((phrase) => !_lowSignalRequestWords.contains(phrase)),
    ).toList();
  }

  Iterable<String> _uniqueStrings(Iterable<String> values) sync* {
    final seen = <String>{};
    for (final value in values) {
      if (seen.add(value)) yield value;
    }
  }

  static const _lowSignalRequestWords = {
    'game',
    'games',
    'anime',
    'manga',
    'title',
    'titles',
    'recommend',
    'recommendation',
    'single',
    'player',
    'single-player',
    'something',
    'where',
    'that',
    'with',
    'from',
    'this',
    'your',
    'user',
    'make',
    'makes',
    'want',
    'like',
    'best',
    'good',
    'great',
    'really',
    'very',
    'much',
  };

  String _serviceDirectRecommendationPrompt({
    required TasteProfile profile,
    required _AiPromptTier tier,
    required _PromptLimits limits,
    required RecommendationQuery query,
    required List<Map<String, Object?>> knownHints,
    required bool allowSearchTools,
  }) {
    final ownedTitles = _ownedTitlesForPrompt(profile, limits);
    if (_isSteamService(profile.serviceName)) {
      return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext('Steam')}
Personally recommend exactly one real Steam PC game from your own knowledge for this user.
This is a direct recommendation, not tag selection and not option reranking. You may choose a game outside the known search-result hints. Use the request as the primary decision, then use the user's game taste as secondary guidance.
The title must be an exact game title that Majika can search for on Steam. Do not invent a game and do not recommend a game the user already owns.
Titles shown in profile evidence are already owned and are taste signals only, never valid recommendations.
Respect required play capabilities when they are present.
${_steamToolInstruction(allowSearchTools)}
Return JSON only. Use exactly these keys: title, reason. Keep reason to one short sentence under 25 words.
${_profilePromptEvidence(profile, tier, limits)}
Game request: ${query.request}
User-selected Steam tags: ${query.selectedTags.join(', ')}
AI-selected Steam tags: ${query.aiSelectedTags.join(', ')}
Required Steam play capabilities: ${query.effectiveFormats().join(', ')}
Known owned-game titles to avoid: ${jsonEncode(ownedTitles)}
Known Steam search-result hints, optional and non-exhaustive: ${jsonEncode(knownHints)}
''';
    }
    if (_isAniListService(profile.serviceName)) {
      return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext('AniList')}
Personally recommend exactly one real anime or manga title from your own knowledge for this user.
This is a direct recommendation, not tag selection and not option reranking. You may choose a title outside the known search-result hints. Use the request, the user's anime/manga taste, and your knowledge of titles as the decision.
The title must be an exact canonical title that Majika can search for on AniList. Do not invent a title and do not recommend a title already in the user's library.
Titles shown in profile evidence are already in the user's library and are taste signals only, never valid recommendations.
Respect requested media types and release formats when they are present.
${_adultRecommendationGuidance(query, supportsAdultContent: true)}
Return JSON only. Use exactly these keys: title, reason. Keep reason to one short sentence under 25 words.
${_profilePromptEvidence(profile, tier, limits)}
Anime or manga request: ${query.request}
Requested AniList media types: ${query.effectiveMediaTypes().join(', ')}
Requested AniList release formats: ${query.effectiveFormats().join(', ')}
Known library titles to avoid: ${jsonEncode(ownedTitles)}
Known AniList search-result hints, optional and non-exhaustive: ${jsonEncode(knownHints)}
''';
    }
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
${_servicePromptContext(profile.serviceName)}
Personally recommend exactly one real title from your own knowledge for this user.
This is a direct recommendation, not tag selection and not option reranking. You may choose a title outside the known search-result hints.
The title must be exact and searchable through ${profile.serviceName}. Do not invent a title and do not recommend a title already in the user's library.
Titles shown in profile evidence are already in the user's library and are taste signals only, never valid recommendations.
${_adultRecommendationGuidance(query, supportsAdultContent: true)}
Return JSON only. Use exactly these keys: title, reason. Keep reason to one short sentence under 25 words.
${_profilePromptEvidence(profile, tier, limits)}
User request: ${query.request}
Requested source types: ${query.effectiveMediaTypes().join(', ')}
Requested formats: ${query.effectiveFormats().join(', ')}
Known library titles to avoid: ${jsonEncode(ownedTitles)}
Known search-result hints, optional and non-exhaustive: ${jsonEncode(knownHints)}
''';
  }

  List<String> _ownedTitlesForPrompt(
    TasteProfile profile,
    _PromptLimits limits,
  ) {
    final limit = limits.profileItemLimit >= _fullPromptLimit
        ? _fullPromptLimit
        : limits.profileItemLimit * 8;
    final titles = <String>{};

    void add(MediaItem? item) {
      final title = item?.title.trim() ?? '';
      if (title.isNotEmpty && titles.length < limit) {
        titles.add(title);
      }
    }

    add(profile.recentActivity);
    for (final item in profile.highRatedItems) {
      add(item);
    }
    for (final item in profile.library) {
      add(item);
    }
    return titles.toList();
  }

  String _homeDirectRecommendationPrompt({
    required List<TasteProfile> profiles,
    required _AiPromptTier tier,
    required _PromptLimits limits,
    required RecommendationQuery query,
    required List<Map<String, Object?>> knownHints,
  }) {
    final availableServices = profiles
        .map((profile) => profile.serviceName)
        .toSet()
        .toList();
    final ownedTitles = {
      for (final profile in profiles)
        profile.serviceName: _ownedTitlesForPrompt(profile, limits),
    };
    final profileEvidence = profiles
        .map((profile) => _profilePromptEvidence(profile, tier, limits))
        .join('\n');
    return '''
Prompt mode: ${tier.name}.
${_promptScopeInstruction(tier)}
Personally recommend exactly one real title from your own knowledge across the user's imported services.
This is the direct Home recommendation, not tag selection and not option reranking. You may choose a title outside the known search-result hints. Use the request as the primary decision, then use the relevant personal profile as secondary guidance.
Choose only from these services: ${availableServices.join(', ')}.
If the request asks for a game, choose Steam. If it asks for anime or manga, choose AniList. For a broad request, choose the strongest personal fit across the available services.
Return an exact title searchable through the chosen service. Do not invent a title and do not recommend anything already in the corresponding library.
Titles shown in profile evidence are already owned and are taste signals only, never valid recommendations.
Respect hard media-type and format/play-capability requirements when they apply to the chosen service.
${_adultRecommendationGuidance(query, supportsAdultContent: availableServices.any(_isAniListService))}
Return JSON only. Use exactly these keys: service, title, reason. The service must exactly match one available service. Keep reason to one short sentence under 25 words.
$profileEvidence
Home request: ${query.request}
Requested media types: ${query.effectiveMediaTypes().join(', ')}
Requested formats or play capabilities: ${query.effectiveFormats().join(', ')}
Known library titles to avoid by service: ${jsonEncode(ownedTitles)}
Known cross-service search-result hints, optional and non-exhaustive: ${jsonEncode(knownHints)}
''';
  }

  String _serviceCandidateDiscoveryPrompt({
    required TasteProfile profile,
    required _AiPromptTier tier,
    required _PromptLimits limits,
    required RecommendationQuery query,
    required List<Map<String, Object?>> knownHints,
    required int limit,
    required bool allowSearchTools,
  }) {
    final ownedTitles = _ownedTitlesForPrompt(profile, limits);
    final isSteam = _isSteamService(profile.serviceName);
    final subject = isSteam
        ? 'real Steam PC games'
        : _isAniListService(profile.serviceName)
        ? 'real anime or manga titles'
        : 'real titles';
    final formatLabel = isSteam
        ? 'Steam play capabilities'
        : _isAniListService(profile.serviceName)
        ? 'AniList formats/media types'
        : 'formats/media types';
    final knownTitles = [
      for (final hint in knownHints)
        if (hint['title']?.toString().trim().isNotEmpty ?? false)
          hint['title'].toString(),
    ];
    return '''
Prompt mode: ${tier.name}.
${_servicePromptContext(profile.serviceName)}
Suggest up to $limit $subject that strongly match this request.
This is a title-discovery pass before API validation. Use your own model knowledge to name likely matches beyond simple tag search.
Use the request as the primary decision. Use the user's profile only as a light tie-breaker.
Return exact titles that should be searchable on ${profile.serviceName}. Do not invent titles and do not suggest titles already in the user's library.
Respect hard $formatLabel when they are present.
${isSteam ? _steamToolInstruction(allowSearchTools) : ''}
Return JSON only. Prefer exactly this shape: {"titles":["..."]}. Titles only, no reasons.
Request: ${query.request}
User-selected tags: ${query.selectedTags.join(', ')}
AI-selected tags: ${query.aiSelectedTags.join(', ')}
Requested media types: ${query.effectiveMediaTypes().join(', ')}
Requested formats or play capabilities: ${query.effectiveFormats().join(', ')}
Known library titles to avoid: ${jsonEncode(ownedTitles)}
Known API result titles, optional and non-exhaustive: ${jsonEncode(knownTitles)}
''';
  }

  AiRecommendationSuggestion? _suggestionFromResponse(
    String response, {
    required String fallbackServiceName,
    Iterable<String> allowedServices = const [],
  }) {
    final serviceLookup = {
      for (final service in allowedServices) _canonicalKey(service): service,
    };
    AiRecommendationSuggestion? suggestion;
    for (final candidate in _jsonObjects(response)) {
      final title = candidate['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;
      final rawService = candidate['service']?.toString().trim() ?? '';
      final serviceName = rawService.isEmpty
          ? fallbackServiceName
          : serviceLookup[_canonicalKey(rawService)] ?? '';
      if (serviceName.isEmpty) continue;
      final reason = candidate['reason']?.toString().trim() ?? '';
      suggestion = AiRecommendationSuggestion(
        title: title,
        serviceName: serviceName,
        reason: reason.isEmpty
            ? 'Chosen as the strongest direct AI recommendation.'
            : reason,
      );
    }
    return suggestion;
  }

  List<AiRecommendationSuggestion> _suggestionsFromResponse(
    String response, {
    required String fallbackServiceName,
    Iterable<String> allowedServices = const [],
    int limit = 5,
  }) {
    final serviceLookup = {
      for (final service in allowedServices) _canonicalKey(service): service,
    };
    final suggestions = <AiRecommendationSuggestion>[];
    final seenTitles = <String>{};

    String serviceNameFor(String rawService) {
      if (rawService.isEmpty) return fallbackServiceName;
      return serviceLookup[_canonicalKey(rawService)] ?? '';
    }

    void addTitle(String title, {String rawService = '', String reason = ''}) {
      title = title.trim();
      if (!_looksLikeSuggestedTitle(title)) return;
      if (!seenTitles.add(_canonicalKey(title))) return;
      final serviceName = serviceNameFor(rawService.trim());
      if (serviceName.isEmpty) return;
      suggestions.add(
        AiRecommendationSuggestion(
          title: title,
          serviceName: serviceName,
          reason: reason.isEmpty
              ? 'Suggested from the AI title-discovery pass.'
              : reason,
        ),
      );
    }

    void addSuggestion(Map candidate) {
      final title = candidate['title']?.toString().trim() ?? '';
      final reason =
          candidate['reason']?.toString().trim() ??
          candidate['reasoning']?.toString().trim() ??
          '';
      addTitle(
        title,
        rawService: candidate['service']?.toString().trim() ?? '',
        reason: reason,
      );
    }

    for (final object in _jsonObjects(response)) {
      final nested = object['suggestions'];
      if (nested is List) {
        for (final entry in nested) {
          if (entry is Map) addSuggestion(entry);
          if (entry is String) addTitle(entry);
          if (suggestions.length >= limit) return suggestions;
        }
      }

      final titles = object['titles'];
      if (titles is List) {
        for (final entry in titles) {
          if (entry is String) addTitle(entry);
          if (entry is Map) addSuggestion(entry);
          if (suggestions.length >= limit) return suggestions;
        }
      }

      if (nested is! List && titles is! List) {
        addSuggestion(object);
      }
      if (suggestions.length >= limit) return suggestions;
    }

    for (final title in _titleFragmentsFromResponse(response)) {
      addTitle(title);
      if (suggestions.length >= limit) return suggestions;
    }

    return suggestions;
  }

  Iterable<String> _titleFragmentsFromResponse(String response) sync* {
    final titleFields = RegExp(
      r'"title"\s*:\s*"((?:\\.|[^"\\])*)"',
      multiLine: true,
    );
    for (final match in titleFields.allMatches(response)) {
      final encoded = match.group(1);
      if (encoded == null || encoded.trim().isEmpty) continue;
      try {
        yield jsonDecode('"$encoded"').toString();
      } catch (_) {
        yield encoded.replaceAll(r'\"', '"').trim();
      }
    }

    final titleArray = RegExp(
      r'"titles"\s*:\s*\[((?:.|\n)*)',
      multiLine: true,
    ).firstMatch(response);
    if (titleArray != null) {
      final quoted = RegExp(r'"((?:\\.|[^"\\])*)"');
      for (final match in quoted.allMatches(titleArray.group(1)!)) {
        final encoded = match.group(1);
        if (encoded == null || encoded.trim().isEmpty) continue;
        try {
          yield jsonDecode('"$encoded"').toString();
        } catch (_) {
          yield encoded.replaceAll(r'\"', '"').trim();
        }
      }
    }

    for (final line in response.split('\n')) {
      var candidate = line.trim();
      if (candidate.isEmpty || candidate.contains(':')) continue;
      candidate = candidate
          .replaceFirst(RegExp(r'^[\-\*\d\.\)\s]+'), '')
          .replaceFirst(RegExp(r'^"+'), '')
          .replaceFirst(RegExp(r'[".,]+$'), '')
          .trim();
      final separator = RegExp(r'\s+-\s+').firstMatch(candidate);
      if (separator != null) {
        candidate = candidate.substring(0, separator.start);
      }
      if (_looksLikeSuggestedTitle(candidate)) yield candidate;
    }
  }

  bool _looksLikeSuggestedTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.length < 2 || trimmed.length > 90) return false;
    if (trimmed.contains('{') || trimmed.contains('}')) return false;
    if (trimmed.contains('`')) return false;
    final lower = trimmed.toLowerCase();
    const blocked = {
      'title',
      'titles',
      'suggestions',
      'reason',
      'reasoning',
      'json',
    };
    if (blocked.contains(lower)) return false;
    return RegExp(r'[a-zA-Z0-9]').hasMatch(trimmed);
  }

  @override
  Future<List<AiRecommendationSuggestion>> suggestRecommendationCandidates(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
    int limit = 5,
  }) async {
    if (!query.isActive || limit <= 0) return const [];
    final baseSettings = await _runtimeSettings();
    final settings = _effectiveSettingsForTask(
      baseSettings,
      task: 'steam_discovery',
      minimumTier: AiModelTrustTier.constrained,
    );
    if (!settings.useLocalAi && textGenerator == null) return const [];
    final discoveryTrust = _trustTierForTask(settings, 'steam_discovery');
    if (_isSteamService(profile.serviceName) &&
        !_meetsTrustTier(discoveryTrust, AiModelTrustTier.constrained)) {
      return _groundedSteamSuggestions(query, limit: limit);
    }
    final allowSearchTools =
        settings.supportsSearchTools && _isSteamService(profile.serviceName);

    final budget = _promptBudget(settings, responseTokens: 768);
    try {
      final packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) => _serviceCandidateDiscoveryPrompt(
          profile: profile,
          tier: budget.tier,
          limits: limits,
          query: query,
          knownHints: _directPickHints(
            knownRecommendations,
            limits.optionLimit,
          ),
          limit: limit,
          allowSearchTools: allowSearchTools,
        ),
      );
      final response = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
        settings: settings,
        externalTools: allowSearchTools ? _steamExternalTools() : const [],
      );
      return _suggestionsFromResponse(
        response,
        fallbackServiceName: profile.serviceName,
        limit: limit,
      );
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<AiRecommendationSuggestion?> suggestRecommendation(
    TasteProfile profile,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  }) async {
    if (!query.isActive) return null;
    final baseSettings = await _runtimeSettings();
    final settings = _effectiveSettingsForTask(
      baseSettings,
      task: 'steam_discovery',
      minimumTier: AiModelTrustTier.constrained,
    );
    if (!settings.useLocalAi && textGenerator == null) return null;
    final discoveryTrust = _trustTierForTask(settings, 'steam_discovery');
    if (_isSteamService(profile.serviceName) &&
        !_meetsTrustTier(discoveryTrust, AiModelTrustTier.constrained)) {
      final suggestions = await _groundedSteamSuggestions(query, limit: 1);
      return suggestions.isEmpty ? null : suggestions.first;
    }
    final allowSearchTools =
        settings.supportsSearchTools && _isSteamService(profile.serviceName);

    final budget = _promptBudget(settings, responseTokens: 768);
    try {
      final packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) => _serviceDirectRecommendationPrompt(
          profile: profile,
          tier: budget.tier,
          limits: limits,
          query: query,
          knownHints: _directPickHints(
            knownRecommendations,
            limits.optionLimit,
          ),
          allowSearchTools: allowSearchTools,
        ),
      );
      final response = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
        settings: settings,
        externalTools: allowSearchTools ? _steamExternalTools() : const [],
      );
      return _suggestionFromResponse(
        response,
        fallbackServiceName: profile.serviceName,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AiRecommendationSuggestion?> suggestHomeRecommendation(
    List<TasteProfile> profiles,
    List<Recommendation> knownRecommendations, {
    required RecommendationQuery query,
  }) async {
    if (!query.isActive || profiles.isEmpty) return null;
    final settings = await _runtimeSettings();
    if (!settings.useLocalAi && textGenerator == null) return null;

    final budget = _promptBudget(settings, responseTokens: 768);
    try {
      final packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) => _homeDirectRecommendationPrompt(
          profiles: profiles,
          tier: budget.tier,
          limits: limits,
          query: query,
          knownHints: _directPickHints(
            knownRecommendations,
            limits.optionLimit,
          ),
        ),
      );
      final response = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
        settings: settings,
      );
      return _suggestionFromResponse(
        response,
        fallbackServiceName: '',
        allowedServices: profiles.map((profile) => profile.serviceName),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AiChatResponse> chatAboutRecommendations(AiChatRequest request) async {
    final settings = await _runtimeSettings();
    if (!settings.useLocalAi && textGenerator == null) {
      return fallback.chatAboutRecommendations(request);
    }

    final budget = _promptBudget(settings, responseTokens: 768);
    try {
      final packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) => _recommendationChatPrompt(
          request: request,
          tier: budget.tier,
          limits: limits,
          allowExplicitContent: settings.allowExplicitContent,
        ),
      );
      final response = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
        settings: settings,
      );
      final parsed = _chatResponseFromModelJson(
        response,
        originalQuery: request.query,
        availableTags: request.availableTags,
        allowExplicitContent: settings.allowExplicitContent,
      );
      if (parsed != null) return parsed;
      final text = response.trim();
      if (text.isNotEmpty) return AiChatResponse(message: text);
    } catch (_) {
      return fallback.chatAboutRecommendations(request);
    }
    return fallback.chatAboutRecommendations(request);
  }

  @override
  Future<Recommendation?> chooseTopRecommendation(
    TasteProfile profile,
    List<Recommendation> recommendations, {
    required RecommendationQuery query,
  }) async {
    if (recommendations.isEmpty) return null;
    final baseSettings = await _runtimeSettings();
    final settings = _effectiveSettingsForTask(
      baseSettings,
      task: 'recommendation_selection',
      minimumTier: AiModelTrustTier.trusted,
    );
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
    if (!_meetsTrustTier(
      _trustTierForTask(settings, 'recommendation_selection'),
      AiModelTrustTier.trusted,
    )) {
      return fallback.chooseTopRecommendation(
        profile,
        selectableRecommendations,
        query: query,
      );
    }

    final budget = _promptBudget(settings, responseTokens: 1024);
    final optionTags = {
      for (final recommendation in selectableRecommendations)
        for (final tag in recommendation.item.tags) tag,
    };
    final requestTags = {
      ...query.selectedTags,
      ...query.aiSelectedTags,
      ...query.inferredTags(optionTags),
    };
    late final _PackedPrompt packed;
    try {
      packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) {
          final options = selectableRecommendations
              .take(limits.optionLimit)
              .map(
                (recommendation) => _serviceTopOptionEvidence(
                  serviceName: profile.serviceName,
                  recommendation: recommendation,
                  tier: budget.tier,
                  requestedFormats: requestedFormats,
                  requireLocalCoOp: requireLocalCoOp,
                  requestTags: requestTags,
                  query: query,
                  tagLimit: limits.optionTagLimit,
                  signalLimit: limits.signalLimit,
                ),
              )
              .toList();
          return _serviceTopRecommendationPrompt(
            profile: profile,
            tier: budget.tier,
            limits: limits,
            query: query,
            requestedFormats: requestedFormats,
            requireLocalCoOp: requireLocalCoOp,
            inferredTags: query.inferredTags(optionTags),
            options: options,
          );
        },
      );
    } catch (_) {
      return fallback.chooseTopRecommendation(
        profile,
        selectableRecommendations,
        query: query,
      );
    }

    try {
      final response = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
        settings: settings,
      );
      Recommendation? chosen;
      String? reason;
      for (final candidate in _jsonObjects(response)) {
        final id = candidate['id']?.toString().trim() ?? '';
        final title = candidate['title']?.toString().trim() ?? '';
        final titleKey = _canonicalKey(title);
        for (final recommendation in selectableRecommendations) {
          if (recommendation.item.id == id ||
              (titleKey.isNotEmpty &&
                  _canonicalKey(recommendation.item.title) == titleKey)) {
            chosen = recommendation;
            reason =
                candidate['reason']?.toString().trim() ??
                candidate['reasoning']?.toString().trim();
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
    final baseSettings = await _runtimeSettings();
    final settings = _effectiveSettingsForTask(
      baseSettings,
      task: 'recommendation_selection',
      minimumTier: AiModelTrustTier.trusted,
    );
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
    if (!_meetsTrustTier(
      _trustTierForTask(settings, 'recommendation_selection'),
      AiModelTrustTier.trusted,
    )) {
      return fallback.chooseHomeRecommendation(
        profiles,
        selectableRecommendations,
        query: query,
      );
    }

    final budget = _promptBudget(settings, responseTokens: 1024);
    late final _PackedPrompt packed;
    try {
      packed = _packPrompt(
        budget: budget,
        initialLimits: _promptLimits(budget.tier),
        build: (limits) {
          final profilesSummary = profiles
              .map(
                (profile) => '${profile.serviceName}: ${profile.primaryTaste}',
              )
              .join(' | ');
          final profileEvidence = profiles
              .map(
                (profile) =>
                    _profilePromptEvidence(profile, budget.tier, limits),
              )
              .join('\n');
          final options = selectableRecommendations
              .take(limits.optionLimit)
              .map(
                (recommendation) => _homeOptionEvidence(
                  recommendation: recommendation,
                  tier: budget.tier,
                  requestedFormats: requestedFormats,
                  requireLocalCoOp: requireLocalCoOp,
                  tagLimit: limits.optionTagLimit,
                ),
              )
              .toList();
          return '''
Prompt mode: ${budget.tier.name}.
${_promptScopeInstruction(budget.tier)}
Pick the single best next recommendation across all services.
This Home prompt can compare AniList anime/manga with Steam games. First filter for the strongest match to the user's search request, then use the most relevant imported profile as secondary guidance. Use tags and score as evidence, not as the whole decision.
If the user asks for a game, prefer Steam GAME options; if they ask for anime/manga, prefer AniList options. If they ask broadly, choose the strongest fit across services.
Only the listed options are eligible for this request.
Each option uses service-specific evidence fields: steamTags and playCapability for Steam, aniListTags and releaseFormat for AniList.
If missingConstraints is empty, that option satisfies the applicable requested constraints.
Return JSON only. Use exactly these keys: id, reason. The id must match one option id. Keep reason to one short sentence under 25 words.
Profiles summary: $profilesSummary
$profileEvidence
Search request: ${query.request}
User-selected tags: ${query.selectedTags.join(', ')}
Requested formats: ${query.formats.join(', ')}
Local co-op required: $requireLocalCoOp
Requested media types: ${query.mediaTypes.join(', ')}
Options: ${jsonEncode(options)}
''';
        },
      );
    } catch (_) {
      return fallback.chooseHomeRecommendation(
        profiles,
        selectableRecommendations,
        query: query,
      );
    }

    try {
      final response = await _generateText(
        packed.prompt,
        maxTokens: budget.responseTokens,
        settings: settings,
      );
      Recommendation? chosen;
      String? reason;
      for (final candidate in _jsonObjects(response)) {
        final id = candidate['id']?.toString().trim() ?? '';
        final title = candidate['title']?.toString().trim() ?? '';
        final titleKey = _canonicalKey(title);
        for (final recommendation in selectableRecommendations) {
          if (recommendation.item.id == id ||
              (titleKey.isNotEmpty &&
                  _canonicalKey(recommendation.item.title) == titleKey)) {
            chosen = recommendation;
            reason =
                candidate['reason']?.toString().trim() ??
                candidate['reasoning']?.toString().trim();
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

  Future<List<AiRecommendationSuggestion>> _groundedSteamSuggestions(
    RecommendationQuery query, {
    required int limit,
  }) async {
    final searchText = query.interpretedRequest.trim().isNotEmpty
        ? query.interpretedRequest.trim()
        : query.searchRequest.trim().isNotEmpty
        ? query.searchRequest.trim()
        : query.request.trim();
    if (searchText.isEmpty) return const [];
    try {
      final results = await searchToolbox.searchSteamGames(
        searchText,
        limit: limit,
      );
      return [
        for (final result in results.take(limit))
          AiRecommendationSuggestion(
            title: result['title']?.toString().trim() ?? '',
            serviceName: 'Steam',
            reason: _groundedSteamReason(result),
          ),
      ].where((suggestion) => suggestion.title.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  String _groundedSteamReason(Map<String, Object?> result) {
    final tags = _stringList(result['tags']);
    if (tags.isNotEmpty) {
      return 'Grounded Steam match from store search: ${tags.take(2).join(' and ')}.';
    }
    final subtitle = result['subtitle']?.toString().trim() ?? '';
    if (subtitle.isNotEmpty) {
      return 'Grounded Steam match from store search: $subtitle.';
    }
    return 'Grounded Steam match from store search.';
  }
}
