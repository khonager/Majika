import 'dart:convert';
import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/ai_console_log.dart';
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

    expect(capturedPrompt, contains('Service context: Steam PC games'));
    expect(capturedPrompt, contains('Service source values: GAME'));
    expect(capturedPrompt, contains('Steam play capability values'));
    expect(capturedPrompt, isNot(contains('Yandere')));
    expect(capturedPrompt, isNot(contains('Mahou Shoujo')));
    expect(interpreted.mediaTypes, contains('GAME'));
    expect(interpreted.formats, contains('SINGLE_PLAYER'));
    expect(interpreted.aiSelectedTags, contains('RPG'));
  });

  test(
    'local AI search prompt omits stale AI tags and false adult state',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"tags":["Mystery"],"formats":[],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"moody mystery"}';
        },
      );

      await service.interpretRecommendationRequest(
        const RecommendationQuery(
          request: 'moody mystery',
          aiSelectedTags: {'Yandere'},
        ),
        availableTags: const ['Mystery', 'Romance'],
      );

      expect(capturedPrompt, isNot(contains('Previously AI selected tags')));
      expect(capturedPrompt, isNot(contains('AI-selected tags')));
      expect(capturedPrompt, isNot(contains('Adult content selected: false')));
      expect(capturedPrompt, contains('infer it from the request text only'));
    },
  );

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

  test(
    'flutter gemma service uses compact tag prompts for tiny models',
    () async {
      late String capturedPrompt;
      late int capturedMaxTokens;
      final availableTags = [
        'Fantasy',
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
      expect(capturedPrompt, contains('High-signal AniList tags'));
      expect(capturedPrompt, contains('Prompt mode: compact'));
      expect(capturedPrompt, contains('Fantasy'));
      expect(capturedPrompt, contains('Magic'));
      expect(capturedPrompt, contains('School'));
      expect(capturedPrompt, isNot(contains('{"tags":["Romance"]')));
      expect(capturedPrompt, contains('Use empty arrays'));
      expect(capturedPrompt, isNot(contains('Generated Tag 40')));
    },
  );

  test(
    'manual and advanced AI search prompts include rich tag context',
    () async {
      late String capturedPrompt;
      final availableTags = [
        'Romance',
        for (var index = 0; index < 90; index++) 'Generated Tag $index',
      ];
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeManual,
          provider: localAiModeManual,
          endpoint: defaultLocalAiEndpoint,
          serverModel: defaultLocalAiModel,
          contextItems: 24,
        ),
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"tags":["Romance"],"formats":[],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"romance"}';
        },
      );

      await service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'romance'),
        availableTags: availableTags,
      );

      expect(capturedPrompt, contains('Prompt mode: rich'));
      expect(capturedPrompt, contains('Generated Tag 89'));
      expect(
        capturedPrompt,
        contains('A later AI prompt will personally pick'),
      );
    },
  );

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

  test('local AI service can use manual copy paste responses', () async {
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeManual,
        provider: localAiModeManual,
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        contextItems: 24,
      ),
    );

    late ManualAiRequest capturedRequest;
    final interpreted = await runZoned(
      () => service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'romance movie'),
        availableTags: const ['Romance', 'Mystery'],
      ),
      zoneValues: {
        manualAiRequestHandlerZoneKey: (ManualAiRequest request) async {
          capturedRequest = request;
          return '{"tags":["Romance"],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"romance movie"}';
        },
      },
    );

    expect(capturedRequest.prompt, contains('Return JSON only'));
    expect(capturedRequest.maxTokens, 1024);
    expect(interpreted.aiSelectedTags, contains('Romance'));
    expect(interpreted.formats, contains('MOVIE'));
  });

  test('local AI service writes prompt and response to console log', () async {
    final log = AiConsoleLog();
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        return '{"tags":["Mystery"],"formats":["TV"],"mediaTypes":["ANIME"],"includeAdult":false}';
      },
    );

    await runZoned(
      () => service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'mystery tv'),
        availableTags: const ['Mystery', 'Romance'],
      ),
      zoneValues: {localAiConsoleLogZoneKey: log},
    );

    expect(log.value, contains('Prompt'));
    expect(log.value, contains('mystery tv'));
    expect(log.value, contains('Response'));
    expect(log.value, contains('"Mystery"'));
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

    expect(capturedPrompt, contains("Prioritize the user's request"));
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

  test(
    'prompt benchmark: rich Steam picker includes personal game evidence',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeManual,
          provider: localAiModeManual,
          endpoint: defaultLocalAiEndpoint,
          serverModel: defaultLocalAiModel,
          contextItems: 24,
        ),
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"id":"steam_portal_like","reason":"Fits their puzzle co-op history and the request."}';
        },
      );

      final profile = _profile(
        serviceName: 'Steam',
        favoriteGenres: const ['Puzzle', 'Co-op'],
        library: [
          _mediaItem(
            'steam_portal_2',
            'Portal 2',
            tags: const ['Puzzle', 'Co-op', 'Comedy'],
            mediaType: 'GAME',
            format: 'CO_OP',
            sourceId: 'com.majika.service.steam',
            playtimeMinutes: 1800,
          ),
        ],
        highRatedItems: [
          _mediaItem(
            'steam_it_takes_two',
            'It Takes Two',
            tags: const ['Co-op', 'Adventure', 'Controller Support'],
            mediaType: 'GAME',
            format: 'CO_OP',
            sourceId: 'com.majika.service.steam',
          ),
        ],
        tagWeights: const {'Puzzle': 4.5, 'Co-op': 4.0},
      );

      await service.chooseTopRecommendation(
        profile,
        [
          _recommendation(
            'steam_high_score',
            'Generic Popular RPG',
            tags: const ['RPG', 'Open World'],
            format: 'SINGLE_PLAYER',
            mediaType: 'GAME',
            sourceId: 'com.majika.service.steam',
          ),
          _recommendation(
            'steam_portal_like',
            'Puzzle Co-op Controller Game',
            tags: const ['Puzzle', 'Co-op', 'Controller Support'],
            format: 'CO_OP',
            mediaType: 'GAME',
            sourceId: 'com.majika.service.steam',
          ),
        ],
        query: const RecommendationQuery(
          request: 'a clever funny co-op game like Portal 2 for controllers',
          mediaTypes: {'GAME'},
          formats: {'CO_OP', 'CONTROLLER'},
        ),
      );

      expect(capturedPrompt, contains('Prompt mode: rich'));
      expect(capturedPrompt, contains('Steam PC games'));
      expect(capturedPrompt, contains('librarySample'));
      expect(capturedPrompt, contains('Portal 2'));
      expect(capturedPrompt, contains('It Takes Two'));
      expect(capturedPrompt, contains('A lower-score option can win'));
      expect(capturedPrompt, isNot(contains('favoriteCharacters')));
    },
  );

  test(
    'prompt benchmark: tiny selected on-device model gets compact context',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeOnDevice,
          provider: 'Gemma',
          endpoint: defaultLocalAiEndpoint,
          serverModel: defaultLocalAiModel,
          deviceModelName: 'Gemma 3 1B IT',
          contextItems: 24,
        ),
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"id":"anilist_1","reason":"Compact pick."}';
        },
      );

      await service.chooseTopRecommendation(
        _profile(
          highRatedItems: [
            _mediaItem('anilist_monogatari', 'Monogatari Series'),
          ],
        ),
        [
          for (var index = 0; index < 8; index++)
            _recommendation('anilist_$index', 'Anime $index'),
        ],
        query: const RecommendationQuery(request: 'surreal mystery anime'),
      );

      expect(capturedPrompt, contains('Prompt mode: compact'));
      expect(capturedPrompt, contains('User taste:'));
      expect(capturedPrompt, isNot(contains('librarySample')));
      expect(capturedPrompt, isNot(contains('Monogatari Series')));
    },
  );

  test(
    'prompt benchmark: Home prompt carries cross-service decision rules',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeExternalCloud,
          provider: externalCloudAiProvider,
          endpoint: defaultLocalAiEndpoint,
          serverModel: defaultLocalAiModel,
          cloudProvider: 'Google Gemini',
          cloudModel: 'gemini-3.1-flash-lite',
          contextItems: 24,
        ),
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"id":"steam_funny","reason":"The request asks for a funny PC game."}';
        },
      );

      await service.chooseHomeRecommendation(
        [
          _profile(serviceName: 'AniList', favoriteGenres: const ['Comedy']),
          _profile(serviceName: 'Steam', favoriteGenres: const ['Co-op']),
        ],
        [
          _recommendation('anilist_comedy', 'Comedy Anime'),
          _recommendation(
            'steam_funny',
            'Funny PC Game',
            tags: const ['Comedy', 'Co-op'],
            mediaType: 'GAME',
            format: 'CO_OP',
            sourceId: 'com.majika.service.steam',
          ),
        ],
        query: const RecommendationQuery(request: 'funny game on my pc'),
      );

      expect(capturedPrompt, contains('Prompt mode: rich'));
      expect(
        capturedPrompt,
        contains('compare AniList anime/manga with Steam games'),
      );
      expect(
        capturedPrompt,
        contains('If the user asks for a game, prefer Steam GAME options'),
      );
      expect(capturedPrompt, contains('AniList: Comedy'));
      expect(capturedPrompt, contains('Steam: Co-op'));
      expect(capturedPrompt, isNot(contains('AI-selected tags')));
    },
  );

  test('local AI runtime settings resolves backend preference', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalAiSettingsKeys.localBackend, localAiBackendGpu);

    final settings = await LocalAiRuntimeSettings.load();

    expect(settings.backend, localAiBackendGpu);
    expect(settings.preferredBackend, PreferredBackend.gpu);
  });

  test(
    'local AI runtime settings loads selected on-device model name',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalAiSettingsKeys.selectedModelName,
        'Gemma 3 1B IT',
      );

      final settings = await LocalAiRuntimeSettings.load();

      expect(settings.deviceModelName, 'Gemma 3 1B IT');
    },
  );

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

TasteProfile _profile({
  String serviceName = 'AniList',
  List<MediaItem> library = const [],
  List<String> favoriteGenres = const ['Mystery'],
  Map<String, double> tagWeights = const {},
  Map<String, double> formatWeights = const {},
  List<MediaItem> highRatedItems = const [],
  MediaItem? recentActivity,
}) {
  return TasteProfile(
    userName: 'tester',
    library: library,
    favoriteGenres: favoriteGenres,
    tagWeights: tagWeights,
    formatWeights: formatWeights,
    formatCounts: const {},
    favoriteCharacters: const [],
    favoriteStaff: const [],
    favoriteStudios: const [],
    highRatedItems: highRatedItems,
    recentActivity: recentActivity,
    completedCount: 0,
    currentCount: 0,
    importedAt: DateTime(2026),
    serviceName: serviceName,
  );
}

MediaItem _mediaItem(
  String id,
  String title, {
  List<String> tags = const ['Mystery'],
  String format = 'TV',
  String mediaType = 'ANIME',
  String sourceId = 'com.majika.service.anilist',
  int? playtimeMinutes,
}) {
  return MediaItem(
    id: id,
    title: title,
    coverUrl: '',
    tags: tags,
    format: format,
    mediaType: mediaType,
    sourceId: sourceId,
    playtimeMinutes: playtimeMinutes,
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
    item: _mediaItem(
      id,
      title,
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
