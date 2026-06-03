import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/local_ai_settings.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('flutter gemma service keeps rule-inferred Steam constraints', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        return '''
```json
{
  "tags": [],
  "formats": ["MULTIPLAYER", "CO_OP"],
  "mediaTypes": ["GAME"],
  "includeAdult": false,
  "searchText": "fun game to play with two players on one pc with controllers"
}
```
''';
      },
    );

    final interpreted = await service.interpretRecommendationRequest(
      const RecommendationQuery(
        request: 'fun game to play with two players on one pc with controllers',
      ),
      availableTags: const [
        'Action',
        'Adventure',
        'Co-op',
        'Controller Support',
      ],
      serviceName: 'Steam',
      allowedMediaTypes: RecommendationQuery.steamMediaTypes,
      allowedFormats: RecommendationQuery.steamFormats,
    );

    expect(interpreted.mediaTypes, contains('GAME'));
    expect(interpreted.formats, contains('CO_OP'));
    expect(interpreted.formats, contains('MULTIPLAYER'));
    expect(interpreted.formats, contains('CONTROLLER'));
  });

  test('flutter gemma service canonicalizes model filter spelling', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        return '{"tags":["single player","role playing"],"formats":["single player"],"mediaTypes":["game"],"includeAdult":false,"searchText":"single player role playing"}';
      },
    );

    final interpreted = await service.interpretRecommendationRequest(
      const RecommendationQuery(request: 'single player role playing'),
      availableTags: const ['Single-player', 'Role Playing'],
      serviceName: 'Steam',
      allowedMediaTypes: RecommendationQuery.steamMediaTypes,
      allowedFormats: RecommendationQuery.steamFormats,
    );

    expect(interpreted.mediaTypes, contains('GAME'));
    expect(interpreted.formats, contains('SINGLE_PLAYER'));
    expect(interpreted.aiSelectedTags, contains('Single-player'));
    expect(interpreted.aiSelectedTags, contains('Role Playing'));
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

  test('local AI service sends bearer auth for cloud providers', () async {
    Object? requestBody;
    Uri? requestUrl;
    Map<String, String>? requestHeaders;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalCloud,
        provider: externalCloudAiProvider,
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        cloudProvider: 'Google Gemini',
        cloudEndpoint:
            'https://generativelanguage.googleapis.com/v1beta/openai',
        cloudModel: 'gemini-3.1-flash-lite',
        cloudApiKey: 'gemini_test_key',
        contextItems: 24,
      ),
      httpPost: (url, {headers, body}) async {
        requestUrl = url;
        requestHeaders = headers;
        requestBody = jsonDecode(body.toString());
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content':
                      '{"tags":["Mystery"],"formats":["TV"],"mediaTypes":["ANIME"],"includeAdult":false}',
                },
              },
            ],
          }),
          200,
        );
      },
    );

    final interpreted = await service.interpretRecommendationRequest(
      const RecommendationQuery(request: 'mystery tv'),
      availableTags: const ['Mystery', 'Romance'],
    );

    expect(
      requestUrl.toString(),
      'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    );
    expect(requestHeaders?['Authorization'], 'Bearer gemini_test_key');
    expect(requestBody, isA<Map<String, dynamic>>());
    expect(
      (requestBody as Map<String, dynamic>)['model'],
      'gemini-3.1-flash-lite',
    );
    expect(interpreted.aiSelectedTags, contains('Mystery'));
    expect(interpreted.formats, contains('TV'));
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

  test('local AI top pick cannot override missing Steam modes', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"id":"steam_gta","reason":"Popular profile match."}';
      },
    );

    final chosen = await service.chooseTopRecommendation(
      _profile(serviceName: 'Steam'),
      [
        _recommendation(
          'steam_gta',
          'Grand Theft Auto V Legacy',
          tags: const ['Action', 'Adventure', 'Controller Support'],
          format: 'SINGLE_PLAYER',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
        _recommendation(
          'steam_coop',
          'Couch Co-op Controller Game',
          tags: const ['Action', 'Co-op', 'Controller Support'],
          format: 'CO_OP',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(
        request: 'fun game to play with two players on one pc with controller',
        mediaTypes: {'GAME'},
        formats: {'MULTIPLAYER', 'CO_OP', 'CONTROLLER'},
      ),
    );

    expect(capturedPrompt, contains('missingFormats'));
    expect(capturedPrompt, contains('Only the listed options are eligible'));
    expect(capturedPrompt, isNot(contains('Grand Theft Auto V Legacy')));
    expect(chosen?.item.id, 'steam_coop');
    expect(chosen?.isAiPick, isFalse);
  });

  test(
    'local rules top pick requires local co-op for one-pc requests',
    () async {
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings.defaults(),
      );

      final chosen = await service.chooseTopRecommendation(
        _profile(serviceName: 'Steam'),
        [
          _recommendation(
            'steam_gta',
            'Grand Theft Auto V Legacy',
            tags: const [
              'Action',
              'Adventure',
              'Co-op',
              'Online Co-op',
              'Controller Support',
            ],
            format: 'SINGLE_PLAYER',
            mediaType: 'GAME',
            sourceId: 'com.majika.service.steam',
          ),
          _recommendation(
            'steam_moving_out',
            'Moving Out',
            tags: const [
              'Action',
              'Casual',
              'Shared/Split Screen Co-op',
              'Controller Support',
            ],
            format: 'CO_OP',
            mediaType: 'GAME',
            sourceId: 'com.majika.service.steam',
          ),
        ],
        query: const RecommendationQuery(
          request:
              'fun game to play with two players on one pc with controllers',
          mediaTypes: {'GAME'},
          formats: {'CO_OP', 'CONTROLLER'},
        ),
      );

      expect(chosen?.item.id, 'steam_moving_out');
      expect(chosen?.isAiPick, isFalse);
    },
  );

  test('local AI service can choose a home recommendation', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        expect(prompt, contains('across all services'));
        expect(prompt, contains('"service":"Steam"'));
        return '{"id":"steam_1","reason":"Best PC fit."}';
      },
    );

    final chosen = await service.chooseHomeRecommendation(
      [_profile()],
      [
        _recommendation('anilist_1', 'Anime Pick'),
        _recommendation(
          'steam_1',
          'Game Pick',
          tags: const ['Comedy'],
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(request: 'funny game on pc'),
    );

    expect(chosen?.item.id, 'steam_1');
    expect(chosen?.isAiPick, isTrue);
    expect(chosen?.reason, 'Best PC fit.');
  });

  test('local AI runtime settings resolves backend preference', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalAiSettingsKeys.localBackend, localAiBackendGpu);

    final settings = await LocalAiRuntimeSettings.load();

    expect(settings.backend, localAiBackendGpu);
    expect(settings.preferredBackend, PreferredBackend.gpu);
  });

  test(
    'local AI runtime settings loads external cloud provider fields',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalAiSettingsKeys.localAiMode,
        localAiModeExternalCloud,
      );
      await prefs.setString(LocalAiSettingsKeys.cloudAiProvider, 'OpenRouter');
      await prefs.setString(
        LocalAiSettingsKeys.cloudEndpoint,
        'https://openrouter.ai/api/v1',
      );
      await prefs.setString(
        LocalAiSettingsKeys.cloudModel,
        'meta-llama/llama-3.2-3b-instruct:free',
      );
      await prefs.setString(LocalAiSettingsKeys.cloudApiKey, 'or_test_key');

      final settings = await LocalAiRuntimeSettings.load();

      expect(settings.useLocalAi, isTrue);
      expect(settings.usesExternalCloud, isTrue);
      expect(settings.cloudProvider, 'OpenRouter');
      expect(
        settings.cloudChatCompletionsUri.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(settings.cloudModel, 'meta-llama/llama-3.2-3b-instruct:free');
      expect(settings.cloudApiKey, 'or_test_key');
    },
  );
}

TasteProfile _profile({String serviceName = 'AniList'}) {
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
    serviceName: serviceName,
  );
}

Recommendation _recommendation(
  String id,
  String title, {
  List<String> tags = const ['Mystery'],
  String format = 'TV',
  String mediaType = 'ANIME',
  String sourceId = 'com.majika.service.anilist',
}) {
  return Recommendation(
    item: MediaItem(
      id: id,
      title: title,
      coverUrl: '',
      tags: tags,
      format: format,
      mediaType: mediaType,
      sourceId: sourceId,
    ),
    matchScore: 80,
    reason: 'Reason',
    signals: const ['Mystery'],
  );
}
