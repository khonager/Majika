import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';

void main() {
  test(
    'flutter gemma service turns model JSON into query selections',
    () async {
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          expect(prompt, contains('romance movie about time travel'));
          return '''
{"tags":["Romance","Time Manipulation"],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"romance movie about time travel"}
''';
        },
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'romance movie about time travel'),
        availableTags: const ['Romance', 'Time Manipulation', 'Yandere'],
      );

      expect(interpreted.selectedTags, isEmpty);
      expect(interpreted.aiSelectedTags, contains('Romance'));
      expect(interpreted.aiSelectedTags, contains('Time Manipulation'));
      expect(interpreted.formats, contains('MOVIE'));
      expect(interpreted.mediaTypes, contains('ANIME'));
    },
  );

  test('flutter gemma service can interpret Steam game filters', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"tags":["RPG"],"formats":["SINGLE_PLAYER"],"mediaTypes":["GAME"],"includeAdult":false,"searchText":"single player rpg"}';
      },
    );

    final interpreted = await service.interpretRecommendationRequest(
      const RecommendationQuery(request: 'single player rpg'),
      availableTags: const ['RPG', 'Strategy'],
      serviceName: 'Steam',
      allowedMediaTypes: RecommendationQuery.steamMediaTypes,
      allowedFormats: RecommendationQuery.steamFormats,
    );

    expect(capturedPrompt, contains('structured Steam filters'));
    expect(capturedPrompt, contains('Allowed mediaTypes: GAME'));
    expect(interpreted.mediaTypes, contains('GAME'));
    expect(interpreted.formats, contains('SINGLE_PLAYER'));
    expect(interpreted.aiSelectedTags, contains('RPG'));
  });

  test(
    'flutter gemma service falls back when model output is malformed',
    () async {
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async => 'not json',
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'obsessed character thriller'),
        availableTags: RecommendationQuery.browsableTags,
      );

      expect(interpreted.aiSelectedTags, contains('Yandere'));
      expect(interpreted.aiSelectedTags, contains('Thriller'));
    },
  );

  test('flutter gemma service can choose an AI top recommendation', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        expect(prompt, contains('Pick the single best recommendation'));
        return '{"id":"anilist_2","reason":"Best fit from the AI pass."}';
      },
    );
    final profile = _profile();
    final recommendations = [
      _recommendation('anilist_1', 'First'),
      _recommendation('anilist_2', 'Second'),
    ];

    final chosen = await service.chooseTopRecommendation(
      profile,
      recommendations,
      query: const RecommendationQuery(request: 'moody mystery'),
    );

    expect(chosen?.item.id, 'anilist_2');
    expect(chosen?.isAiPick, isTrue);
    expect(chosen?.reason, 'Best fit from the AI pass.');
  });

  test('flutter gemma service ignores echoed JSON examples', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        expect(prompt, isNot(contains('anilist_123')));
        return '''
{"id":"anilist_123","reason":"short reason"}
{"id":"anilist_2","reason":"Actual fit from the options."}
''';
      },
    );

    final chosen = await service.chooseTopRecommendation(_profile(), [
      _recommendation('anilist_1', 'First'),
      _recommendation('anilist_2', 'Second'),
    ], query: const RecommendationQuery(request: 'magic school'));

    expect(chosen?.item.id, 'anilist_2');
    expect(chosen?.reason, 'Actual fit from the options.');
  });

  test('flutter gemma service uses compact tag prompts', () async {
    late String capturedPrompt;
    late int capturedMaxTokens;
    final availableTags = [
      'Magic',
      'School',
      for (var index = 0; index < 80; index++) 'Generated Tag $index',
    ];
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeOnDevice,
        provider: 'FunctionGemma',
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        contextItems: 8,
      ),
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        capturedMaxTokens = maxTokens;
        return '{"tags":["Fantasy"],"formats":[],"mediaTypes":[],"includeAdult":false}';
      },
    );

    await service.interpretRecommendationRequest(
      const RecommendationQuery(request: 'like harry potter'),
      availableTags: availableTags,
    );

    expect(capturedMaxTokens, 1024);
    expect(capturedPrompt, contains('Allowed tags:'));
    expect(capturedPrompt, contains('Fantasy'));
    expect(capturedPrompt, contains('Magic'));
    expect(capturedPrompt, contains('School'));
    expect(capturedPrompt, isNot(contains('{"tags":["Romance"]')));
    expect(capturedPrompt, contains('Use empty arrays'));
    expect(capturedPrompt, isNot(contains('Generated Tag 40')));
  });

  test(
    'flutter gemma service uses the last query-shaped JSON object',
    () async {
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async => '''
{"tags":["Romance"],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":false}
{"tags":["Mystery"],"formats":["TV"],"mediaTypes":["ANIME"],"includeAdult":false}
''',
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'mystery tv'),
        availableTags: const ['Romance', 'Mystery'],
      );

      expect(interpreted.aiSelectedTags, contains('Mystery'));
      expect(interpreted.aiSelectedTags, isNot(contains('Romance')));
      expect(interpreted.formats, contains('TV'));
    },
  );

  test('local AI service can use an OpenAI-compatible local server', () async {
    Object? requestBody;
    Uri? requestUrl;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalServer,
        provider: externalLocalAiProvider,
        endpoint: 'http://127.0.0.1:52625',
        serverModel: 'gemma3:4b',
        contextItems: 24,
      ),
      httpPost: (url, {headers, body}) async {
        requestUrl = url;
        requestBody = jsonDecode(body.toString());
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content':
                      '{"tags":["Romance"],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":false}',
                },
              },
            ],
          }),
          200,
        );
      },
    );

    final interpreted = await service.interpretRecommendationRequest(
      const RecommendationQuery(request: 'romance movie'),
      availableTags: const ['Romance', 'Mystery'],
    );

    expect(requestUrl.toString(), 'http://127.0.0.1:52625/v1/chat/completions');
    expect(requestBody, isA<Map<String, dynamic>>());
    expect((requestBody as Map<String, dynamic>)['model'], 'gemma3:4b');
    expect(
      (requestBody as Map<String, dynamic>)['messages'],
      isA<List<dynamic>>(),
    );
    expect(interpreted.aiSelectedTags, contains('Romance'));
    expect(interpreted.formats, contains('MOVIE'));
  });

  test('local AI service respects the configured context budget', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeOnDevice,
        provider: 'Qwen',
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        contextItems: 8,
      ),
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"id":"anilist_1","reason":"Compact context."}';
      },
    );

    final recommendations = [
      for (var index = 0; index < 12; index++)
        _recommendation('anilist_$index', 'Title $index'),
    ];

    await service.chooseTopRecommendation(
      _profile(),
      recommendations,
      query: const RecommendationQuery(request: 'mystery'),
    );

    expect(capturedPrompt, contains('anilist_2'));
    expect(capturedPrompt, isNot(contains('anilist_3')));
  });

  test('local AI top-pick prompt emphasizes request fit', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeOnDevice,
        provider: 'Qwen',
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        contextItems: 24,
      ),
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"id":"anilist_wistoria","reason":"Best request fit."}';
      },
    );

    await service.chooseTopRecommendation(_profile(), [
      _recommendation(
        'anilist_slime',
        'Tensei Shitara Slime Datta Ken 4th Season',
        tags: const ['Action', 'Adventure', 'Fantasy', 'Magic'],
      ),
      _recommendation(
        'anilist_wistoria',
        'Tsue to Tsurugi no Wistoria Season 2',
        tags: const ['Action', 'Adventure', 'Fantasy', 'Magic', 'School'],
      ),
    ], query: const RecommendationQuery(request: 'like harry potter'));

    expect(capturedPrompt, contains('Prioritize the search request'));
    expect(capturedPrompt, contains('Request-inferred tags:'));
    expect(
      capturedPrompt,
      contains('"requestTags":["Fantasy","Magic","School"]'),
    );
  });
}

TasteProfile _profile() {
  return TasteProfile(
    userName: 'tester',
    library: const [],
    favoriteGenres: const ['Mystery'],
    tagWeights: const {},
    formatWeights: const {},
    formatCounts: const {},
    favoriteCharacters: const [],
    favoriteStaff: const [],
    favoriteStudios: const [],
    highRatedItems: const [],
    recentActivity: null,
    completedCount: 0,
    currentCount: 0,
    importedAt: DateTime(2026),
  );
}

Recommendation _recommendation(
  String id,
  String title, {
  List<String> tags = const ['Mystery'],
}) {
  return Recommendation(
    item: MediaItem(id: id, title: title, coverUrl: '', tags: tags),
    matchScore: 80,
    reason: 'Reason',
    signals: const ['Mystery'],
  );
}
