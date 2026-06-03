import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';

const _fixturePath = 'test/fixtures/ai_prompt_benchmarks.json';

void main() {
  test('exports benchmark prompts from the real local AI service', () async {
    final outputPath = Platform.environment['AI_PROMPT_BENCHMARK_EXPORT'];
    final stubResponses =
        Platform.environment['AI_PROMPT_BENCHMARK_STUBS'] == '1';
    final fixture = _Fixture.load(_fixturePath);
    final responses = <Map<String, dynamic>>[];

    for (final scenario in fixture.scenarios) {
      final captured = await _captureScenarioPrompt(
        scenario,
        stubResponses: stubResponses,
      );
      expect(
        captured.prompt,
        contains('Prompt mode: ${scenario.promptTier}.'),
        reason: scenario.id,
      );
      responses.add({
        'scenarioId': scenario.id,
        'task': scenario.task,
        'service': scenario.service,
        'promptTier': scenario.promptTier,
        'prompt': captured.prompt,
        'response': captured.response,
      });
    }

    expect(responses, hasLength(fixture.scenarios.length));
    if (outputPath != null && outputPath.trim().isNotEmpty) {
      final output = {
        'model':
            Platform.environment['AI_PROMPT_BENCHMARK_MODEL'] ??
            'manual-model-under-test',
        'promptRevision':
            Platform.environment['AI_PROMPT_BENCHMARK_REVISION'] ??
            'working-tree',
        'fixture': _fixturePath,
        'instructions':
            'Paste each prompt into the model named above, replace response with the raw model output, then run tool/ai_prompt_benchmark.dart --responses $outputPath.',
        'responses': responses,
      };
      final file = File(outputPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(output),
      );
    }
  });
}

Future<_CapturedPrompt> _captureScenarioPrompt(
  _Scenario scenario, {
  required bool stubResponses,
}) async {
  String? capturedPrompt;
  final stubResponse = scenario.stubResponse;
  final service = FlutterGemmaLocalAiService(
    settingsLoader: () async => _settingsForTier(scenario.promptTier),
    textGenerator: (prompt, maxTokens) async {
      capturedPrompt = prompt;
      return stubResponse;
    },
  );

  switch (scenario.task) {
    case 'search_filter':
      await service.interpretRecommendationRequest(
        RecommendationQuery(request: scenario.request),
        availableTags: scenario.availableTags,
        serviceName: scenario.service,
        allowedMediaTypes: _mediaTypesForService(scenario.service),
        allowedFormats: _formatsForService(scenario.service),
      );
      break;
    case 'top_pick':
      await service.chooseTopRecommendation(
        _profileForScenario(scenario),
        _recommendationsForScenario(scenario),
        query: RecommendationQuery(request: scenario.request),
      );
      break;
    case 'home_pick':
      await service.chooseHomeRecommendation(
        _profilesForScenario(scenario),
        _recommendationsForScenario(scenario),
        query: RecommendationQuery(request: scenario.request),
      );
      break;
    default:
      throw FormatException(
        'Unsupported benchmark task "${scenario.task}" in ${scenario.id}.',
      );
  }

  return _CapturedPrompt(
    prompt: capturedPrompt ?? '',
    response: stubResponses ? stubResponse : '',
  );
}

LocalAiRuntimeSettings _settingsForTier(String promptTier) {
  return switch (promptTier) {
    'compact' => const LocalAiRuntimeSettings(
      useLocalAi: true,
      useAiForSearch: true,
      mode: localAiModeOnDevice,
      provider: 'Benchmark tiny local model',
      endpoint: defaultLocalAiEndpoint,
      serverModel: defaultLocalAiModel,
      deviceModelName: 'Gemma 3 1B IT',
      contextItems: 8,
    ),
    'balanced' => const LocalAiRuntimeSettings(
      useLocalAi: true,
      useAiForSearch: true,
      mode: localAiModeExternalServer,
      provider: externalLocalAiProvider,
      endpoint: defaultLocalAiEndpoint,
      serverModel: 'benchmark-balanced-3b',
      contextItems: 24,
    ),
    _ => const LocalAiRuntimeSettings(
      useLocalAi: true,
      useAiForSearch: true,
      mode: localAiModeExternalCloud,
      provider: externalCloudAiProvider,
      endpoint: defaultLocalAiEndpoint,
      serverModel: defaultLocalAiModel,
      cloudProvider: 'Benchmark rich model',
      cloudEndpoint: defaultCloudAiEndpoint,
      cloudModel: defaultCloudAiModel,
      cloudApiKey: 'benchmark-placeholder',
      contextItems: 48,
    ),
  };
}

TasteProfile _profileForScenario(_Scenario scenario) {
  final profileSignals = scenario.profileSignals;
  final favoriteTags = _stringList(profileSignals['favoriteTags']);
  final highRatedTitles = _stringList(profileSignals['highRated']);
  final service = scenario.service == 'Steam' ? 'Steam' : 'AniList';
  return TasteProfile(
    userName: '${service.toLowerCase()}_benchmark',
    library: [
      for (final title in highRatedTitles)
        _mediaItem(
          id: '${service.toLowerCase()}_history_${_slug(title)}',
          title: title,
          service: service,
          tags: favoriteTags,
          rating: 9.2,
          status: 'COMPLETED',
        ),
    ],
    favoriteGenres: favoriteTags,
    tagWeights: {for (final tag in favoriteTags) tag: 8},
    formatWeights: const {},
    formatCounts: const {},
    favoriteCharacters: const [],
    favoriteStaff: const [],
    favoriteStudios: const [],
    highRatedItems: [
      for (final title in highRatedTitles)
        _mediaItem(
          id: '${service.toLowerCase()}_rated_${_slug(title)}',
          title: title,
          service: service,
          tags: favoriteTags,
          rating: 9.4,
          status: 'COMPLETED',
        ),
    ],
    recentActivity: null,
    completedCount: highRatedTitles.length,
    currentCount: 0,
    importedAt: DateTime.fromMillisecondsSinceEpoch(0),
    serviceName: service,
    serviceId: _sourceIdForService(service),
  );
}

List<TasteProfile> _profilesForScenario(_Scenario scenario) {
  final profiles = scenario.profiles;
  if (profiles.isEmpty) return [_profileForScenario(scenario)];
  return [
    for (final profile in profiles)
      TasteProfile(
        userName: '${profile.service.toLowerCase()}_benchmark',
        library: const [],
        favoriteGenres: profile.favoriteTags,
        tagWeights: {for (final tag in profile.favoriteTags) tag: 8},
        formatWeights: const {},
        formatCounts: const {},
        favoriteCharacters: const [],
        favoriteStaff: const [],
        favoriteStudios: const [],
        highRatedItems: const [],
        recentActivity: null,
        completedCount: 3,
        currentCount: 0,
        importedAt: DateTime.fromMillisecondsSinceEpoch(0),
        serviceName: profile.service,
        serviceId: _sourceIdForService(profile.service),
      ),
  ];
}

List<Recommendation> _recommendationsForScenario(_Scenario scenario) {
  final options = scenario.options.isEmpty
      ? [
          _Option(
            id: 'anilist_compact_mystery',
            title: 'Compact Mystery Candidate',
            service: 'AniList',
            mediaType: 'ANIME',
            score: 82,
            tags: const ['Mystery', 'Psychological', 'Surreal'],
          ),
        ]
      : scenario.options;

  return [
    for (final option in options)
      Recommendation(
        item: _mediaItem(
          id: option.id,
          title: option.title,
          service: option.service.isEmpty ? scenario.service : option.service,
          tags: option.tags,
          mediaType: option.mediaType,
          rating: option.score / 10,
          description:
              '${option.title} benchmark description for ${scenario.request}.',
        ),
        matchScore: option.score,
        reason:
            'Benchmark ranker reason for ${option.title}: ${option.tags.take(3).join(', ')}.',
        signals: option.tags,
      ),
  ];
}

MediaItem _mediaItem({
  required String id,
  required String title,
  required String service,
  required List<String> tags,
  String mediaType = '',
  double? rating,
  String? status,
  String? description,
}) {
  final isSteam = service == 'Steam';
  return MediaItem(
    id: id,
    title: title,
    coverUrl: '',
    tags: tags,
    rating: rating,
    subtitle: isSteam ? 'PC game' : 'TV',
    sourceId: _sourceIdForService(service),
    mediaType: mediaType.isNotEmpty ? mediaType : (isSteam ? 'GAME' : 'ANIME'),
    format: isSteam ? _steamFormatFromTags(tags) : 'TV',
    status: status,
    description: description,
    siteUrl: isSteam
        ? 'https://store.steampowered.com/app/${_slug(id)}'
        : 'https://anilist.co/anime/${_slug(id)}',
  );
}

String _steamFormatFromTags(List<String> tags) {
  final normalized = tags
      .map((tag) => tag.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ''))
      .toSet();
  if (normalized.contains('coop')) return 'CO_OP';
  if (normalized.contains('multiplayer')) return 'MULTIPLAYER';
  if (normalized.contains('singleplayer')) return 'SINGLE_PLAYER';
  return 'UNKNOWN';
}

List<String> _mediaTypesForService(String service) {
  if (service == 'Steam') return RecommendationQuery.steamMediaTypes;
  if (service == 'Home') return RecommendationQuery.allMediaTypes;
  return RecommendationQuery.aniListMediaTypes;
}

List<String> _formatsForService(String service) {
  if (service == 'Steam') return RecommendationQuery.steamFormats;
  if (service == 'Home') return RecommendationQuery.allFormats;
  return RecommendationQuery.aniListFormats;
}

String _sourceIdForService(String service) {
  return service == 'Steam'
      ? 'com.majika.service.steam'
      : 'com.majika.service.anilist';
}

String _slug(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item != null && item.toString().trim().isNotEmpty)
        item.toString().trim(),
  ];
}

Map<String, dynamic> _readJsonMap(String path) {
  final file = File(path);
  if (!file.existsSync()) throw ArgumentError('File does not exist: $path');
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object.');
  }
  return decoded;
}

class _Fixture {
  final List<_Scenario> scenarios;

  const _Fixture({required this.scenarios});

  factory _Fixture.load(String path) {
    final decoded = _readJsonMap(path);
    final scenarios = decoded['scenarios'];
    if (scenarios is! List) {
      throw const FormatException('Invalid benchmark fixture shape.');
    }
    return _Fixture(
      scenarios: [
        for (final scenario in scenarios)
          _Scenario.fromJson(Map<String, dynamic>.from(scenario as Map)),
      ],
    );
  }
}

class _Scenario {
  final String id;
  final String service;
  final String promptTier;
  final String task;
  final String request;
  final List<String> availableTags;
  final Map<String, dynamic> expectedJson;
  final Map<String, dynamic> profileSignals;
  final List<_ProfileSpec> profiles;
  final List<_Option> options;

  const _Scenario({
    required this.id,
    required this.service,
    required this.promptTier,
    required this.task,
    required this.request,
    required this.availableTags,
    required this.expectedJson,
    required this.profileSignals,
    required this.profiles,
    required this.options,
  });

  factory _Scenario.fromJson(Map<String, dynamic> json) {
    return _Scenario(
      id: json['id'] as String,
      service: json['service']?.toString() ?? 'AniList',
      promptTier: json['promptTier']?.toString() ?? 'balanced',
      task: json['task']?.toString() ?? 'search_filter',
      request: json['request']?.toString() ?? '',
      availableTags: _stringList(json['availableTags']),
      expectedJson: Map<String, dynamic>.from(
        json['expectedJsonShape'] as Map? ?? const {},
      ),
      profileSignals: Map<String, dynamic>.from(
        json['profileSignals'] as Map? ?? const {},
      ),
      profiles: [
        for (final profile in json['profiles'] as List? ?? const [])
          _ProfileSpec.fromJson(Map<String, dynamic>.from(profile as Map)),
      ],
      options: [
        for (final option in json['options'] as List? ?? const [])
          _Option.fromJson(Map<String, dynamic>.from(option as Map)),
      ],
    );
  }

  String get stubResponse {
    final response = <String, dynamic>{};
    for (final entry in expectedJson.entries) {
      if (entry.key == 'reasonContains') {
        response['reason'] = _stringList(entry.value).join(' ');
      } else {
        response[entry.key] = entry.value;
      }
    }
    if (!response.containsKey('id') && options.isNotEmpty) {
      response['id'] = options.first.id;
    }
    if (!response.containsKey('reason') && response.containsKey('id')) {
      response['reason'] = 'Benchmark stub response.';
    }
    return jsonEncode(response);
  }
}

class _ProfileSpec {
  final String service;
  final List<String> favoriteTags;

  const _ProfileSpec({required this.service, required this.favoriteTags});

  factory _ProfileSpec.fromJson(Map<String, dynamic> json) {
    return _ProfileSpec(
      service: json['service']?.toString() ?? 'AniList',
      favoriteTags: _stringList(json['favoriteTags']),
    );
  }
}

class _Option {
  final String id;
  final String title;
  final String service;
  final String mediaType;
  final double score;
  final List<String> tags;

  const _Option({
    required this.id,
    required this.title,
    required this.service,
    required this.mediaType,
    required this.score,
    required this.tags,
  });

  factory _Option.fromJson(Map<String, dynamic> json) {
    return _Option(
      id: json['id'] as String,
      title: json['title']?.toString() ?? json['id'].toString(),
      service: json['service']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 80,
      tags: _stringList(json['tags']),
    );
  }
}

class _CapturedPrompt {
  final String prompt;
  final String response;

  const _CapturedPrompt({required this.prompt, required this.response});
}
