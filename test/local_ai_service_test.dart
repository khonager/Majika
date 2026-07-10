import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/ai_search_tools.dart';
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

  test('prompt benchmark fixture covers required scenario categories', () {
    final file = File('test/fixtures/ai_prompt_benchmarks.json');
    final decoded = jsonDecode(file.readAsStringSync());
    final scenarios = decoded['scenarios'] as List<dynamic>;
    final ids = scenarios
        .map((scenario) => (scenario as Map<String, dynamic>)['id'])
        .toSet();

    expect(ids, contains('steam_filter_no_anime_tags'));
    expect(
      ids,
      contains('steam_compact_preserves_official_tags_beyond_subset'),
    );
    expect(ids, contains('anilist_filter_keeps_specific_request_text'));
    expect(
      ids,
      contains('anilist_adult_request_infers_adult_without_false_warning'),
    );
    expect(ids, contains('steam_personal_pick_can_choose_lower_score'));
    expect(ids, contains('home_prefers_steam_for_pc_game_request'));
    expect(ids, contains('compact_model_preserves_safety_and_scope'));
    expect(decoded['scoring'], isA<Map<String, dynamic>>());
  });

  test('query inference does not turn word fragments into hard filters', () {
    const query = RecommendationQuery(
      request: 'find a deeply personal mystery recommendation',
    );

    expect(query.inferredFormats(), isNot(contains('ONA')));
    expect(query.inferredMediaTypes(), isNot(contains('GAME')));
    expect(query.inferredTags(const ['Mystery']), contains('Mystery'));
  });

  test(
    'query inference treats timetravel as time manipulation, not travel',
    () {
      const query = RecommendationQuery(
        request: 'a romance film involving timetravel',
      );

      expect(
        query.inferredTags(const ['Romance', 'Time Manipulation', 'Travel']),
        contains('Time Manipulation'),
      );
      expect(
        query.inferredTags(const ['Romance', 'Time Manipulation', 'Travel']),
        isNot(contains('Travel')),
      );
    },
  );

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

  test(
    'flutter gemma service sanitizes bloated search text and ignores adult hallucinations',
    () async {
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async => '''
{"tags":[],"formats":["MOVIE"],"mediaTypes":["ANIME"],"includeAdult":true,"searchText":"romance film time travel anime movie romance film time travel movie romance film time travel anime movie"}
''',
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(
          request: 'a romance film involving timetravel',
        ),
        availableTags: const ['Romance', 'Time Manipulation', 'Travel'],
      );

      expect(interpreted.searchRequest, 'a romance film involving timetravel');
      expect(interpreted.aiSelectedTags, contains('Romance'));
      expect(interpreted.aiSelectedTags, contains('Time Manipulation'));
      expect(interpreted.aiSelectedTags, isNot(contains('Travel')));
      expect(interpreted.includeAdult, isFalse);
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
    expect(capturedPrompt, contains('Steam play capability values'));
    expect(
      capturedPrompt,
      contains('exactly these keys: tags, formats, searchText'),
    );
    expect(capturedPrompt, isNot(contains('includeAdult')));
    expect(capturedPrompt, isNot(contains('mediaTypes')));
    expect(capturedPrompt, isNot(contains('AniList release format values')));
    expect(
      capturedPrompt,
      contains('For obscure official Steam tags that are not listed'),
    );
    expect(capturedPrompt, isNot(contains('Yandere')));
    expect(capturedPrompt, isNot(contains('Mahou Shoujo')));
    expect(interpreted.mediaTypes, contains('GAME'));
    expect(interpreted.formats, contains('SINGLE_PLAYER'));
    expect(interpreted.aiSelectedTags, contains('RPG'));
  });

  test('AniList search prompt uses only the AniList search contract', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"tags":["Romance"],"formats":["TV"],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"school romance"}';
      },
    );

    await service.interpretRecommendationRequest(
      const RecommendationQuery(request: 'school romance anime'),
      availableTags: const ['Romance', 'School'],
      serviceName: 'AniList',
      allowedMediaTypes: RecommendationQuery.aniListMediaTypes,
      allowedFormats: RecommendationQuery.aniListFormats,
    );

    expect(
      capturedPrompt,
      contains('Service context: AniList anime and manga'),
    );
    expect(capturedPrompt, contains('AniList media type values'));
    expect(capturedPrompt, contains('AniList release format values'));
    expect(
      capturedPrompt,
      contains(
        'exactly these keys: tags, formats, mediaTypes, includeAdult, searchText',
      ),
    );
    expect(
      capturedPrompt,
      isNot(contains("formats field is Majika's transport field")),
    );
    expect(capturedPrompt, isNot(contains('Steam play capability values')));
  });

  test('AniList interpretation drops stale release format filters', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"tags":["Work","Super Power"],"formats":["MANGA"],"mediaTypes":["ANIME","MANGA"],"includeAdult":false,"searchText":"normal job secretly powerful"}';
      },
    );

    final interpreted = await service.interpretRecommendationRequest(
      const RecommendationQuery(
        request:
            'something about a normal 9-5 job but the main character is actually super powerful',
        interpretedRequest: 'old manga search',
        formats: {'MANGA'},
        mediaTypes: {'MANGA'},
      ),
      availableTags: const ['Comedy', 'Super Power', 'Work'],
      serviceName: 'AniList',
      allowedMediaTypes: RecommendationQuery.aniListMediaTypes,
      allowedFormats: RecommendationQuery.aniListFormats,
    );

    expect(capturedPrompt, isNot(contains('filters already active: MANGA')));
    expect(interpreted.formats, isEmpty);
    expect(interpreted.aiSelectedTags, contains('Super Power'));
    expect(interpreted.aiSelectedTags, contains('Work'));
  });

  test('flutter gemma service accepts broader official Steam tags', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeOnDevice,
        provider: 'tiny benchmark model',
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        deviceModelName: 'Gemma 3 1B IT',
        contextItems: 8,
      ),
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"tags":["Souls-like","Action RPG"],"formats":["SINGLE_PLAYER"],"mediaTypes":["GAME"],"includeAdult":false,"searchText":"hard boss fights"}';
      },
    );

    final interpreted = await service.interpretRecommendationRequest(
      const RecommendationQuery(request: 'hard unforgiving boss fights'),
      availableTags: RecommendationQuery.steamBrowsableTags,
      serviceName: 'Steam',
      allowedMediaTypes: RecommendationQuery.steamMediaTypes,
      allowedFormats: RecommendationQuery.steamFormats,
    );

    expect(capturedPrompt, contains('Prompt mode: compact'));
    expect(
      capturedPrompt,
      contains('High-signal Steam tag subset for this small-model prompt'),
    );
    expect(
      capturedPrompt,
      contains('For obscure official Steam tags that are not listed'),
    );
    expect(interpreted.aiSelectedTags, contains('Souls-like'));
    expect(interpreted.aiSelectedTags, contains('Action RPG'));
    expect(interpreted.formats, contains('SINGLE_PLAYER'));
  });

  test(
    'flutter gemma service exposes Steam adult tags for sexual requests',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeOnDevice,
          provider: 'tiny benchmark model',
          endpoint: defaultLocalAiEndpoint,
          serverModel: defaultLocalAiModel,
          deviceModelName: 'Gemma 3 1B IT',
          contextItems: 8,
        ),
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"tags":["Sexual Content"],"formats":["SINGLE_PLAYER"],"searchText":"dating sim"}';
        },
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'horny and naughty sexy'),
        availableTags: RecommendationQuery.steamBrowsableTags,
        serviceName: 'Steam',
        allowedMediaTypes: RecommendationQuery.steamMediaTypes,
        allowedFormats: RecommendationQuery.steamFormats,
      );

      expect(
        capturedPrompt,
        contains('For adult/sexual Steam requests, use Steam tags'),
      );
      expect(capturedPrompt, contains('Sexual Content'));
      expect(capturedPrompt, contains('Nudity'));
      expect(capturedPrompt, contains('NSFW'));
      expect(interpreted.includeAdult, isTrue);
      expect(interpreted.aiSelectedTags, contains('Sexual Content'));
      expect(interpreted.formats, contains('SINGLE_PLAYER'));
    },
  );

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

  test(
    'local AI search honors explicit-content permission from settings',
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
          allowExplicitContent: true,
        ),
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"tags":["Romance"],"formats":[],"mediaTypes":["ANIME"],"includeAdult":false,"searchText":"romance"}';
        },
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'romance'),
        availableTags: const ['Romance', 'Hentai'],
      );

      expect(capturedPrompt, contains('Adult/NSFW content is permitted'));
      expect(capturedPrompt, isNot(contains('Adult content selected: false')));
      expect(interpreted.includeAdult, isFalse);
    },
  );

  test(
    'Steam search interpretation drops stale active controller filters from a repeated request',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"tags":[],"formats":["CONTROLLER"],"searchText":"boring office worker tasks"}';
        },
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(
          request:
              'i want to pretend to be a boring office worker who gets to solve tasks',
          interpretedRequest: 'boring office worker, solve tasks, controller',
          formats: {'CONTROLLER'},
        ),
        availableTags: RecommendationQuery.steamBrowsableTags,
        serviceName: 'Steam',
        allowedMediaTypes: RecommendationQuery.steamMediaTypes,
        allowedFormats: RecommendationQuery.steamFormats,
      );

      expect(
        capturedPrompt,
        isNot(
          contains(
            'User-selected play capability filters already active: CONTROLLER',
          ),
        ),
      );
      expect(interpreted.formats, isEmpty);
      expect(interpreted.searchRequest, 'boring office worker tasks');
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

  test('AI search failure asks before using fallback rules', () async {
    var handled = 0;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        throw StateError('invalid api key');
      },
    );

    final interpreted = await runZoned(
      () => service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'single player rpg'),
        availableTags: const ['RPG', 'Strategy'],
        serviceName: 'Steam',
        allowedMediaTypes: RecommendationQuery.steamMediaTypes,
        allowedFormats: RecommendationQuery.steamFormats,
      ),
      zoneValues: {
        aiFailureFallbackHandlerZoneKey:
            (AiFailureFallbackRequest request) async {
              handled += 1;
              expect(request.operation, contains('Steam search'));
              expect(request.error.toString(), contains('invalid api key'));
              return AiFailureFallbackChoice.useFallback;
            },
      },
    );

    expect(handled, 1);
    expect(interpreted.aiSelectedTags, contains('RPG'));
    expect(interpreted.formats, contains('SINGLE_PLAYER'));
  });

  test(
    'AI search failure can cancel instead of using fallback rules',
    () async {
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          throw StateError('invalid api key');
        },
      );

      await expectLater(
        runZoned(
          () => service.interpretRecommendationRequest(
            const RecommendationQuery(request: 'single player rpg'),
            availableTags: const ['RPG', 'Strategy'],
            serviceName: 'Steam',
            allowedMediaTypes: RecommendationQuery.steamMediaTypes,
            allowedFormats: RecommendationQuery.steamFormats,
          ),
          zoneValues: {
            aiFailureFallbackHandlerZoneKey:
                (AiFailureFallbackRequest request) async =>
                    AiFailureFallbackChoice.cancel,
          },
        ),
        throwsA(isA<AiFallbackCanceledException>()),
      );
    },
  );

  test('flutter gemma service can choose an AI top recommendation', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        expect(prompt, contains('Pick the single best AniList'));
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

  test(
    'AI picker accepts title-shaped option responses from small models',
    () async {
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          return '{"title":"Untitled Goose Game","reasoning":"It best matches the request for a funny game."}';
        },
      );

      final chosen = await service.chooseTopRecommendation(
        _profile(serviceName: 'Steam'),
        [
          _recommendation(
            'steam_cyberpunk',
            'Cyberpunk 2077',
            tags: const ['RPG', 'Single-player'],
            mediaType: 'GAME',
            format: 'SINGLE_PLAYER',
            sourceId: 'com.majika.service.steam',
          ),
          _recommendation(
            'steam_goose',
            'Untitled Goose Game',
            tags: const ['Action', 'Single-player'],
            mediaType: 'GAME',
            format: 'SINGLE_PLAYER',
            sourceId: 'com.majika.service.steam',
          ),
        ],
        query: const RecommendationQuery(
          request: 'fun game that makes you laugh a lot',
          aiSelectedTags: {'Comedy', 'Funny'},
          formats: {'SINGLE_PLAYER'},
        ),
      );

      expect(chosen?.item.id, 'steam_goose');
      expect(chosen?.reason, 'It best matches the request for a funny game.');
      expect(chosen?.isAiPick, isTrue);
    },
  );

  test(
    'Steam picker prompt prioritizes request fit over profile shape',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"id":"steam_funi","reason":"It is built around silly comedy rather than incidental jokes."}';
        },
      );

      final chosen = await service.chooseTopRecommendation(
        _profile(serviceName: 'Steam'),
        [
          _recommendation(
            'steam_gta',
            'Grand Theft Auto V Legacy',
            tags: const ['Action', 'Adventure', 'Single-player'],
            mediaType: 'GAME',
            format: 'SINGLE_PLAYER',
            sourceId: 'com.majika.service.steam',
          ),
          _recommendation(
            'steam_funi',
            'Funi Raccoon Game',
            tags: const ['Comedy', 'Funny', 'Single-player'],
            mediaType: 'GAME',
            format: 'SINGLE_PLAYER',
            sourceId: 'com.majika.service.steam',
          ),
        ],
        query: const RecommendationQuery(
          request: 'a fun single player game that makes you laugh a lot',
          aiSelectedTags: {'Comedy', 'Funny'},
          formats: {'SINGLE_PLAYER'},
        ),
      );

      expect(chosen?.item.id, 'steam_funi');
      expect(
        capturedPrompt,
        contains('First filter for the strongest match to the game request'),
      );
      expect(
        capturedPrompt,
        contains('Steam taste profile only as secondary guidance'),
      );
      expect(
        capturedPrompt,
        contains(
          'Write the reason around why the chosen game fits the request',
        ),
      );
      expect(capturedPrompt, contains('AI-selected Steam tags: Comedy, Funny'));
      expect(
        capturedPrompt,
        contains('"requestFitEvidence":["tag:Single-player"]'),
      );
      expect(
        capturedPrompt,
        contains(
          '"requestFitEvidence":["tag:Comedy","tag:Funny","tag:Single-player"]',
        ),
      );
    },
  );

  test('AI can directly suggest a Steam game outside fetched options', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"title":"Outer Wilds","reason":"Its discovery-driven exploration fits the request and profile."}';
      },
    );

    final suggestion = await service.suggestRecommendation(
      _profile(
        serviceName: 'Steam',
        library: [
          _mediaItem(
            'steam_owned',
            'Portal 2',
            mediaType: 'GAME',
            format: 'CO_OP',
            sourceId: 'com.majika.service.steam',
          ),
        ],
      ),
      [
        _recommendation(
          'steam_known',
          'Known Search Result',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(
        request: 'a game about uncovering a mystery through exploration',
        mediaTypes: {'GAME'},
      ),
    );

    expect(suggestion?.title, 'Outer Wilds');
    expect(suggestion?.serviceName, 'Steam');
    expect(
      capturedPrompt,
      contains('Personally recommend exactly one real Steam PC game'),
    );
    expect(
      capturedPrompt,
      contains('not tag selection and not option reranking'),
    );
    expect(capturedPrompt, contains('outside the known search-result hints'));
    expect(capturedPrompt, contains('Portal 2'));
    expect(capturedPrompt, contains('Known Search Result'));
    expect(
      capturedPrompt,
      isNot(contains('Only the listed Steam game options are eligible')),
    );
  });

  test('AI can suggest multiple Steam candidate titles to resolve', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '''
{"suggestions":[
  {"title":"Untitled Goose Game","reason":"Built around slapstick mischief."},
  {"title":"There Is No Game: Wrong Dimension","reasoning":"A meta comedy adventure."},
  {"service":"AniList","title":"Nichijou","reason":"Wrong service for this pass."},
  {"title":"Untitled Goose Game","reason":"Duplicate should be ignored."}
]}
''';
      },
    );

    final suggestions = await service.suggestRecommendationCandidates(
      _profile(
        serviceName: 'Steam',
        library: [
          _mediaItem(
            'steam_owned',
            'Portal 2',
            mediaType: 'GAME',
            format: 'CO_OP',
            sourceId: 'com.majika.service.steam',
          ),
        ],
      ),
      [
        _recommendation(
          'steam_funnel',
          'Funnel Runners',
          tags: const ['Action', 'Survival'],
          mediaType: 'GAME',
          format: 'SINGLE_PLAYER',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(
        request: 'a fun single player game that makes you laugh a lot',
        aiSelectedTags: {'Comedy', 'Funny'},
        mediaTypes: {'GAME'},
        formats: {'SINGLE_PLAYER'},
      ),
      limit: 3,
    );

    expect(suggestions.map((suggestion) => suggestion.title), [
      'Untitled Goose Game',
      'There Is No Game: Wrong Dimension',
    ]);
    expect(suggestions.first.serviceName, 'Steam');
    expect(suggestions.last.reason, 'A meta comedy adventure.');
    expect(capturedPrompt, contains('Suggest up to 3 real Steam PC games'));
    expect(capturedPrompt, contains('title-discovery pass'));
    expect(capturedPrompt, contains('beyond simple tag search'));
    expect(capturedPrompt, contains('Titles only, no reasons'));
    expect(capturedPrompt, contains('AI-selected tags: Comedy, Funny'));
    expect(capturedPrompt, contains('Known API result titles'));
    expect(capturedPrompt, contains('Funnel Runners'));
    expect(capturedPrompt, contains('Portal 2'));
  });

  test('AI title discovery recovers titles from truncated JSON', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        return '''
```json
{"suggestions":[
  {"title":"Untitled Goose Game","reason":"A pure comedy sandbox where you play
  {"title":"There Is No Game: Wrong Dimension","reason":"Meta comedy
```
''';
      },
    );

    final suggestions = await service.suggestRecommendationCandidates(
      _profile(serviceName: 'Steam'),
      const [],
      query: const RecommendationQuery(
        request: 'fun game that makes you laugh a lot',
        aiSelectedTags: {'Comedy', 'Funny'},
        mediaTypes: {'GAME'},
        formats: {'SINGLE_PLAYER'},
      ),
      limit: 5,
    );

    expect(suggestions.map((suggestion) => suggestion.title), [
      'Untitled Goose Game',
      'There Is No Game: Wrong Dimension',
    ]);
    expect(
      suggestions.every((suggestion) => suggestion.serviceName == 'Steam'),
      isTrue,
    );
  });

  test(
    'direct AniList prompt prioritizes high-rated owned titles to avoid',
    () async {
      late String capturedPrompt;
      final highRatedOwned = _mediaItem(
        'anilist_high_rated',
        'No Game No Life',
      );
      final library = [
        for (var index = 0; index < 12; index++)
          _mediaItem('anilist_owned_$index', 'Owned Anime $index'),
        highRatedOwned,
      ];
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"title":"Odd Taxi","reason":"An unseen approachable pick."}';
        },
      );

      await service.suggestRecommendation(
        _profile(library: library, highRatedItems: [highRatedOwned]),
        const [],
        query: const RecommendationQuery(
          request: 'something good for a person who never watched anime',
          mediaTypes: {'ANIME'},
        ),
      );

      expect(
        capturedPrompt,
        contains('Known library titles to avoid: ["No Game No Life"'),
      );
      expect(capturedPrompt, contains('"Owned Anime 11"'));
      expect(
        capturedPrompt,
        contains('taste signals only, never valid recommendations'),
      );
    },
  );

  test('AI has a distinct direct Home recommendation prompt', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"service":"AniList","title":"Odd Taxi","reason":"The strongest cross-service mystery fit."}';
      },
    );

    final suggestion = await service.suggestHomeRecommendation(
      [
        _profile(serviceName: 'AniList'),
        _profile(serviceName: 'Steam', favoriteGenres: const ['Puzzle']),
      ],
      [
        _recommendation('anilist_known', 'Known Anime'),
        _recommendation(
          'steam_known',
          'Known Game',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(request: 'surprise me with a mystery'),
    );

    expect(suggestion?.serviceName, 'AniList');
    expect(suggestion?.title, 'Odd Taxi');
    expect(capturedPrompt, contains('direct Home recommendation'));
    expect(capturedPrompt, contains('across the user\'s imported services'));
    expect(
      capturedPrompt,
      contains('taste signals only, never valid recommendations'),
    );
    expect(
      capturedPrompt,
      contains('Choose only from these services: AniList, Steam'),
    );
    expect(capturedPrompt, contains('Known cross-service search-result hints'));
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
        const RecommendationQuery(request: 'magic school adventure'),
        availableTags: availableTags,
      );

      expect(capturedMaxTokens, 1024);
      expect(
        capturedPrompt,
        contains('High-signal AniList tag subset for this small-model prompt'),
      );
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
      expect(interpreted.formats, contains('SERIES'));
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

  test(
    'Steam title discovery falls back to grounded store search for unsupported local models',
    () async {
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeOnDevice,
          provider: 'tiny local test model',
          endpoint: defaultLocalAiEndpoint,
          serverModel: defaultLocalAiModel,
          deviceModelName: 'Gemma 3 1B IT',
          contextItems: 8,
        ),
        searchToolbox: AiSearchToolbox(
          httpGet: (url, {headers}) async {
            if (url.path.contains('/storesearch/')) {
              return http.Response(
                jsonEncode({
                  'items': [
                    {'id': 1001},
                    {'id': 1002},
                  ],
                }),
                200,
              );
            }
            final appId = url.queryParameters['appids'];
            if (appId == '1001') {
              return http.Response(
                jsonEncode({
                  '1001': {
                    'success': true,
                    'data': {
                      'steam_appid': 1001,
                      'name': 'VE GSIM Crane Simulator',
                      'short_description': 'Operate heavy cranes.',
                      'genres': [
                        {'description': 'Simulation'},
                      ],
                      'categories': [
                        {'description': 'Single-player'},
                      ],
                    },
                  },
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                '1002': {
                  'success': true,
                  'data': {
                    'steam_appid': 1002,
                    'name': 'VE GSIM Tower Crane Simulator',
                    'short_description': 'Tower crane operations.',
                    'genres': [
                      {'description': 'Simulation'},
                    ],
                    'categories': [
                      {'description': 'Single-player'},
                    ],
                  },
                },
              }),
              200,
            );
          },
        ),
      );

      final suggestions = await service.suggestRecommendationCandidates(
        _profile(serviceName: 'Steam'),
        const [],
        query: const RecommendationQuery(
          request: 'a game about operating a big crane',
          formats: {'SINGLE_PLAYER'},
          mediaTypes: {'GAME'},
        ),
        limit: 2,
      );

      expect(suggestions.map((item) => item.title), [
        'VE GSIM Crane Simulator',
        'VE GSIM Tower Crane Simulator',
      ]);
      expect(
        suggestions.first.reason,
        contains('Grounded Steam match from store search'),
      );
    },
  );

  test(
    'on-device AI falls back to configured cloud model when unavailable',
    () async {
      Object? requestBody;
      Uri? requestUrl;
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeOnDevice,
          provider: 'unsupported local model',
          endpoint: defaultLocalAiEndpoint,
          serverModel: defaultLocalAiModel,
          deviceModelName: 'Unsupported Tiny Model',
          cloudProvider: 'Google Gemini',
          cloudEndpoint: defaultCloudAiEndpoint,
          cloudModel: defaultCloudAiModel,
          cloudApiKey: 'cloud-test-key',
          contextItems: 8,
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
                        '{"tags":["Simulation"],"formats":["SINGLE_PLAYER"],"searchText":"operating a big crane"}',
                  },
                },
              ],
            }),
            200,
          );
        },
      );

      final interpreted = await service.interpretRecommendationRequest(
        const RecommendationQuery(
          request: 'a game about operating a big crane',
        ),
        availableTags: const ['Simulation', 'Puzzle'],
        serviceName: 'Steam',
        allowedMediaTypes: RecommendationQuery.steamMediaTypes,
        allowedFormats: RecommendationQuery.steamFormats,
      );

      expect(requestUrl.toString(), defaultCloudAiEndpoint);
      expect(
        (requestBody as Map<String, dynamic>)['model'],
        defaultCloudAiModel,
      );
      expect(interpreted.aiSelectedTags, contains('Simulation'));
      expect(interpreted.formats, contains('SINGLE_PLAYER'));
    },
  );

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
        cloudModel: 'gemini-2.5-flash-lite',
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
      'gemini-2.5-flash-lite',
    );
    expect(interpreted.aiSelectedTags, contains('Mystery'));
    expect(interpreted.formats, contains('SERIES'));
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

  test('local AI service writes cloud failures to console log', () async {
    final log = AiConsoleLog();
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalCloud,
        provider: externalCloudAiProvider,
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        cloudProvider: 'Google Gemini',
        cloudEndpoint: defaultCloudAiEndpoint,
        cloudModel: defaultCloudAiModel,
        cloudApiKey: 'gemini_test_key',
        contextItems: 24,
      ),
      httpPost: (url, {headers, body}) async {
        return http.Response(
          '{"error":{"message":"models/gemini-3.1-flash-lite is not found"}}',
          404,
        );
      },
    );

    final interpreted = await runZoned(
      () => service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'mystery tv'),
        availableTags: const ['Mystery', 'Romance'],
      ),
      zoneValues: {localAiConsoleLogZoneKey: log},
    );

    expect(interpreted.aiSelectedTags, contains('Mystery'));
    expect(log.value, contains('AI request failed'));
    expect(log.value, contains('HTTP 404'));
    expect(log.value, contains('gemini-3.1-flash-lite'));
  });

  test('local AI service logs response shape when text is missing', () async {
    final log = AiConsoleLog();
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalServer,
        provider: externalLocalAiProvider,
        endpoint: defaultLocalAiEndpoint,
        serverModel: 'gemma4:latest',
        contextItems: 24,
      ),
      httpPost: (url, {headers, body}) async {
        return http.Response(
          '{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":null,"reasoning_content":"I considered broad action adventure tags."}}]}',
          200,
        );
      },
    );

    await runZoned(
      () => service.interpretRecommendationRequest(
        const RecommendationQuery(request: 'mystery tv'),
        availableTags: const ['Mystery', 'Romance'],
      ),
      zoneValues: {localAiConsoleLogZoneKey: log},
    );

    expect(log.value, contains('provider=local server'));
    expect(log.value, contains('model=gemma4:latest'));
    expect(log.value, contains('Model reasoning'));
    expect(log.value, contains('AI response shape'));
    expect(log.value, contains('content=null/0 chars'));
    expect(log.value, contains('Raw AI response excerpt'));
    expect(log.value, contains('AI request failed'));
  });

  test('local AI retries when reasoning consumes the response budget', () async {
    final log = AiConsoleLog();
    var calls = 0;
    Map<String, dynamic>? retryPayload;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalServer,
        provider: externalLocalAiProvider,
        endpoint: defaultLocalAiEndpoint,
        serverModel: 'gemma4:latest',
        contextItems: 24,
      ),
      httpPost: (url, {headers, body}) async {
        calls += 1;
        if (calls == 1) {
          return http.Response(
            '{"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"","reasoning":"I identified likely titles but ran out of budget."}}]}',
            200,
          );
        }
        retryPayload = jsonDecode(body.toString()) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"{\\"titles\\":[\\"Elemental Adventure\\"]}"}}]}',
          200,
        );
      },
    );

    final suggestions = await runZoned(
      () => service.suggestRecommendationCandidates(
        _profile(serviceName: 'Steam'),
        const [],
        query: const RecommendationQuery(request: 'elemental adventure game'),
      ),
      zoneValues: {localAiConsoleLogZoneKey: log},
    );

    expect(calls, 2);
    expect(retryPayload?['max_tokens'], greaterThanOrEqualTo(1024));
    expect(retryPayload?['response_format'], {'type': 'json_object'});
    expect(retryPayload?['reasoning_effort'], 'none');
    expect(retryPayload?['think'], isFalse);
    expect(suggestions.single.title, 'Elemental Adventure');
    expect(log.value, contains('retrying final JSON only'));
    expect(log.value, contains('Received retry HTTP 200'));
  });

  test('AI recommendation chat prompt includes current context', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"message":"Hollow Knight fits your mystery taste.","actions":[{"type":"explainRecommendation","label":"Explain top pick","recommendationId":"steam_hollow"}]}';
      },
    );

    final response = await service.chatAboutRecommendations(
      AiChatRequest(
        surface: AiChatSurface.service,
        serviceName: 'Steam',
        profiles: [_profile(serviceName: 'Steam')],
        query: const RecommendationQuery(request: 'moody metroidvania'),
        recommendations: [
          _recommendation(
            'steam_hollow',
            'Hollow Knight',
            tags: const ['Metroidvania', 'Atmospheric'],
            mediaType: 'GAME',
            sourceId: 'com.majika.service.steam',
          ),
        ],
        messages: [AiChatMessage(role: AiChatRole.user, text: 'Why this one?')],
        availableTags: RecommendationQuery.steamBrowsableTags,
        availableServices: const ['Steam'],
      ),
    );

    expect(capturedPrompt, contains('Prompt mode: compact'));
    expect(capturedPrompt, contains('moody metroidvania'));
    expect(capturedPrompt, contains('User taste: Mystery'));
    expect(capturedPrompt, contains('Hollow Knight'));
    expect(capturedPrompt, contains('Why this one?'));
    expect(response.message, contains('Hollow Knight'));
    expect(
      response.actions.single.type,
      AiChatActionType.explainRecommendation,
    );
    expect(response.actions.single.recommendationId, 'steam_hollow');
  });

  test(
    'compact AI chat prompt trims history and recommendation context',
    () async {
      late String capturedPrompt;
      final service = FlutterGemmaLocalAiService(
        settingsLoader: () async => const LocalAiRuntimeSettings(
          useLocalAi: true,
          useAiForSearch: true,
          mode: localAiModeExternalServer,
          provider: externalLocalAiProvider,
          endpoint: defaultLocalAiEndpoint,
          serverModel: 'tiny',
          contextItems: 48,
          contextWindowOverrideTokens: 4096,
        ),
        textGenerator: (prompt, maxTokens) async {
          capturedPrompt = prompt;
          return '{"message":"Compact answer.","actions":[]}';
        },
      );

      await service.chatAboutRecommendations(
        AiChatRequest(
          surface: AiChatSurface.home,
          serviceName: 'Home',
          profiles: [_profile()],
          query: const RecommendationQuery(request: 'mystery'),
          recommendations: [
            for (var index = 0; index < 6; index++)
              _recommendation('anilist_$index', 'Chat Title $index'),
          ],
          messages: [
            for (var index = 0; index < 8; index++)
              AiChatMessage(role: AiChatRole.user, text: 'old message $index'),
          ],
        ),
      );

      expect(capturedPrompt, contains('Token budget: 4K context'));
      expect(capturedPrompt, contains('Prompt mode: compact'));
      expect(capturedPrompt, contains('Chat Title 2'));
      expect(capturedPrompt, isNot(contains('Chat Title 3')));
      expect(capturedPrompt, isNot(contains('old message 3')));
      expect(capturedPrompt, contains('old message 4'));
    },
  );

  test('AI recommendation chat parses query actions', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async {
        return '{"message":"Let us search for co-op games.","actions":[{"type":"runSearch","label":"Run co-op search","query":{"request":"fun local co-op","tags":["Co-op"],"formats":["CO_OP"],"mediaTypes":["GAME"],"includeAdult":false}}]}';
      },
    );

    final response = await service.chatAboutRecommendations(
      AiChatRequest(
        surface: AiChatSurface.service,
        serviceName: 'Steam',
        profiles: [_profile(serviceName: 'Steam')],
        query: const RecommendationQuery(),
        recommendations: const [],
        messages: [
          AiChatMessage(role: AiChatRole.user, text: 'Find couch co-op'),
        ],
        availableTags: RecommendationQuery.steamBrowsableTags,
      ),
    );

    final action = response.actions.single;
    expect(action.type, AiChatActionType.runSearch);
    expect(action.label, 'Run co-op search');
    expect(action.query?.request, 'fun local co-op');
    expect(action.query?.aiSelectedTags, contains('Co-op'));
    expect(action.query?.formats, contains('CO_OP'));
    expect(action.query?.mediaTypes, contains('GAME'));
  });

  test('malformed AI chat output falls back to plain response', () async {
    final service = FlutterGemmaLocalAiService(
      textGenerator: (prompt, maxTokens) async => 'Plain chat answer.',
    );

    final response = await service.chatAboutRecommendations(
      AiChatRequest(
        surface: AiChatSurface.service,
        serviceName: 'AniList',
        profiles: [_profile()],
        query: const RecommendationQuery(request: 'mystery'),
        recommendations: const [],
        messages: [AiChatMessage(role: AiChatRole.user, text: 'What now?')],
      ),
    );

    expect(response.message, 'Plain chat answer.');
    expect(response.actions, isEmpty);
  });

  test('AI chat actions cannot enable adult content when hidden', () async {
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalServer,
        provider: externalLocalAiProvider,
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        contextItems: 24,
        allowExplicitContent: false,
      ),
      textGenerator: (prompt, maxTokens) async {
        return '{"message":"I will keep explicit content hidden.","actions":[{"type":"runSearch","query":{"request":"hentai romance","tags":["Hentai"],"includeAdult":true}}]}';
      },
    );

    final response = await service.chatAboutRecommendations(
      AiChatRequest(
        surface: AiChatSurface.service,
        serviceName: 'AniList',
        profiles: [_profile()],
        query: const RecommendationQuery(),
        recommendations: const [],
        messages: [AiChatMessage(role: AiChatRole.user, text: 'adult romance')],
        availableTags: RecommendationQuery.aniListBrowsableTags,
      ),
    );

    final query = response.actions.single.query;
    expect(query?.includeAdult, isFalse);
    expect(query?.excludeAdult, isTrue);
    expect(query?.aiSelectedTags, isNot(contains('Hentai')));
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

  test('small model context packs prompts within a token budget', () async {
    late String capturedPrompt;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalServer,
        provider: externalLocalAiProvider,
        endpoint: defaultLocalAiEndpoint,
        serverModel: 'custom-small-model',
        contextItems: 48,
        contextWindowOverrideTokens: 4096,
      ),
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"id":"anilist_0","reason":"Packed fit."}';
      },
    );

    await service.chooseTopRecommendation(
      _profile(
        library: [
          for (var index = 0; index < 100; index++)
            _mediaItem(
              'history_$index',
              'Very Long History Evidence $index ${'details ' * 30}',
            ),
        ],
      ),
      [
        for (var index = 0; index < 30; index++)
          _recommendation(
            'anilist_$index',
            'Very Long Candidate $index ${'details ' * 30}',
          ),
      ],
      query: const RecommendationQuery(request: 'mystery'),
    );

    expect(capturedPrompt, contains('Token budget: 4K context'));
    expect(capturedPrompt, contains('Prompt mode: compact'));
    expect(capturedPrompt, contains('anilist_2'));
    expect(capturedPrompt, isNot(contains('anilist_3')));
    expect((utf8.encode(capturedPrompt).length / 3).ceil(), lessThan(2816));
  });

  test('context-window resolver chooses tiers from active model capacity', () {
    expect(
      resolveAiContextWindowTokens(
        mode: localAiModeOnDevice,
        modelName: 'Gemma 3 1B IT',
      ),
      4096,
    );
    expect(
      resolveAiContextWindowTokens(
        mode: localAiModeExternalServer,
        modelName: 'qwen3:4b-instruct',
      ),
      32768,
    );
    expect(
      resolveAiContextWindowTokens(
        mode: localAiModeExternalCloud,
        modelName: 'gemini-2.5-flash-lite',
        cloudProvider: 'Google Gemini',
      ),
      1048576,
    );
    expect(
      resolveAiContextWindowTokens(
        mode: localAiModeExternalCloud,
        modelName: 'openrouter/free',
        cloudProvider: 'OpenRouter',
      ),
      200000,
    );
    expect(
      resolveAiContextWindowTokens(
        mode: localAiModeExternalCloud,
        modelName: 'qwen/qwen3-coder:free',
        cloudProvider: 'OpenRouter',
      ),
      1048576,
    );
  });

  test('context-window resolver covers every selectable free cloud model', () {
    for (final entry in freeCloudAiModelsByProvider.entries) {
      for (final model in entry.value) {
        expect(
          resolveAiContextWindowTokens(
            mode: localAiModeExternalCloud,
            modelName: model,
            cloudProvider: entry.key,
          ),
          cloudAiModelContextWindowTokens[model],
          reason: '${entry.key} $model should have an explicit context window',
        );
      }
    }
  });

  test('context-window override does not mask selectable cloud models', () {
    expect(
      resolveAiContextWindowOverrideTokens(
        overrideTokens: 131072,
        mode: localAiModeExternalCloud,
        modelName: 'gemini-2.5-flash-lite',
        cloudProvider: 'Google Gemini',
      ),
      isNull,
    );
    expect(
      resolveAiContextWindowOverrideTokens(
        overrideTokens: 32768,
        mode: localAiModeExternalCloud,
        modelName: 'custom/free-model',
        cloudProvider: 'Custom OpenAI-compatible',
      ),
      32768,
    );
  });

  test(
    'cloud runtime settings use selectable model context over override',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalAiSettingsKeys.localAiMode,
        localAiModeExternalCloud,
      );
      await prefs.setString(
        LocalAiSettingsKeys.cloudAiProvider,
        'Google Gemini',
      );
      await prefs.setString(
        LocalAiSettingsKeys.cloudModel,
        'gemini-2.5-flash-lite',
      );
      await prefs.setInt(LocalAiSettingsKeys.aiContextWindowTokens, 131072);

      final settings = await LocalAiRuntimeSettings.load();

      expect(settings.contextWindowOverrideTokens, 131072);
      expect(settings.contextWindowTokens, 1048576);
    },
  );

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
        return '{"id":"anilist_magic_school","reason":"Best request fit."}';
      },
    );

    await service.chooseTopRecommendation(
      _profile(),
      [
        _recommendation(
          'anilist_fantasy_quest',
          'Fantasy Quest',
          tags: const ['Action', 'Adventure', 'Fantasy', 'Magic'],
        ),
        _recommendation(
          'anilist_magic_school',
          'Magic School Adventure',
          tags: const ['Action', 'Adventure', 'Fantasy', 'Magic', 'School'],
        ),
      ],
      query: const RecommendationQuery(request: 'magic school adventure'),
    );

    expect(capturedPrompt, contains("Prioritize the user's request"));
    expect(capturedPrompt, contains('Request-inferred AniList tags:'));
    expect(
      capturedPrompt,
      contains('"matchedRequestAniListTags":["Fantasy","Magic","School"]'),
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

    expect(capturedPrompt, contains('missingPlayCapabilities'));
    expect(
      capturedPrompt,
      contains('Only the listed Steam game options are eligible'),
    );
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
      expect(capturedPrompt, contains('"steamTags"'));
      expect(capturedPrompt, contains('"playCapability"'));
      expect(capturedPrompt, contains('"playtimeMinutes"'));
      expect(capturedPrompt, isNot(contains('favoriteCharacters')));
      expect(capturedPrompt, isNot(contains('"aniListTags"')));
      expect(capturedPrompt, isNot(contains('"releaseFormat"')));
      expect(capturedPrompt, isNot(contains('"isAdult"')));
    },
  );

  test('rich AniList picker omits Steam-only evidence', () async {
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
        return '{"id":"anilist_pick","reason":"Fits the AniList profile."}';
      },
    );

    await service.chooseTopRecommendation(
      _profile(
        library: [
          _mediaItem(
            'anilist_history',
            'History Title',
            tags: const ['Romance', 'School'],
          ),
        ],
      ),
      [
        _recommendation(
          'anilist_pick',
          'AniList Pick',
          tags: const ['Romance', 'School'],
        ),
      ],
      query: const RecommendationQuery(request: 'school romance anime'),
    );

    expect(capturedPrompt, contains('"aniListTags"'));
    expect(capturedPrompt, contains('"releaseFormat"'));
    expect(capturedPrompt, contains('"isAdult"'));
    expect(capturedPrompt, isNot(contains('"steamTags"')));
    expect(capturedPrompt, isNot(contains('"playCapability"')));
    expect(capturedPrompt, isNot(contains('"playtimeMinutes"')));
  });

  test(
    'profile summaries and explanations use service-specific prompts',
    () async {
      final capturedPrompts = <String>[];
      final service = FlutterGemmaLocalAiService(
        textGenerator: (prompt, maxTokens) async {
          capturedPrompts.add(prompt);
          return 'Service-specific result.';
        },
      );
      final steamProfile = _profile(
        serviceName: 'Steam',
        library: [
          _mediaItem(
            'steam_played',
            'Played Game',
            sourceId: 'com.majika.service.steam',
            mediaType: 'GAME',
            format: 'SINGLE_PLAYER',
            playtimeMinutes: 600,
          ),
        ],
      );
      final aniListProfile = _profile();

      await service.summarizeProfile(steamProfile);
      await service.explainRecommendation(
        steamProfile,
        _recommendation(
          'steam_pick',
          'Steam Pick',
          sourceId: 'com.majika.service.steam',
          mediaType: 'GAME',
          format: 'SINGLE_PLAYER',
        ),
      );
      await service.summarizeProfile(aniListProfile);
      await service.explainRecommendation(
        aniListProfile,
        _recommendation('anilist_pick', 'AniList Pick'),
      );

      expect(capturedPrompts[0], contains('Steam game taste profile'));
      expect(capturedPrompts[0], contains('Most-played games'));
      expect(capturedPrompts[0], isNot(contains('Favorite characters')));
      expect(capturedPrompts[1], contains('Playtime evidence'));
      expect(capturedPrompts[1], isNot(contains('Favorite characters')));
      expect(capturedPrompts[2], contains('AniList anime and manga taste'));
      expect(capturedPrompts[2], contains('Favorite characters'));
      expect(capturedPrompts[2], isNot(contains('Most-played games')));
      expect(capturedPrompts[3], contains('Release format'));
      expect(capturedPrompts[3], isNot(contains('Playtime evidence')));
    },
  );

  test(
    'rich manual picker includes all supplied profile and option evidence',
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
          return '{"id":"anilist_candidate_24","reason":"Best full-context match."}';
        },
      );

      final chosen = await service.chooseTopRecommendation(
        _profile(
          library: [
            for (var index = 0; index < 45; index++)
              _mediaItem('anilist_library_$index', 'Library Evidence $index'),
          ],
        ),
        [
          for (var index = 0; index < 25; index++)
            _recommendation(
              'anilist_candidate_$index',
              'Candidate Evidence $index',
            ),
        ],
        query: const RecommendationQuery(request: 'use my complete history'),
      );

      expect(capturedPrompt, contains('Prompt mode: rich'));
      expect(capturedPrompt, contains('Full-context scope'));
      expect(capturedPrompt, contains('Library Evidence 44'));
      expect(capturedPrompt, contains('Candidate Evidence 24'));
      expect(chosen?.item.id, 'anilist_candidate_24');
    },
  );

  test('rich Home picker includes every eligible cross-service option', () async {
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
        cloudModel: 'gemini-2.5-flash-lite',
        contextItems: 24,
      ),
      textGenerator: (prompt, maxTokens) async {
        capturedPrompt = prompt;
        return '{"id":"steam_candidate_21","reason":"Best cross-service fit."}';
      },
    );

    final chosen = await service.chooseHomeRecommendation(
      [_profile(serviceName: 'AniList'), _profile(serviceName: 'Steam')],
      [
        for (var index = 0; index < 21; index++)
          _recommendation('anilist_candidate_$index', 'Anime Candidate $index'),
        _recommendation(
          'steam_candidate_21',
          'Steam Candidate 21',
          mediaType: 'GAME',
          sourceId: 'com.majika.service.steam',
        ),
      ],
      query: const RecommendationQuery(request: 'pick across everything'),
    );

    expect(capturedPrompt, contains('Full-context scope'));
    expect(capturedPrompt, contains('Steam Candidate 21'));
    expect(chosen?.item.id, 'steam_candidate_21');
  });

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
          cloudModel: 'gemini-2.5-flash-lite',
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

  test('local AI runtime settings loads explicit-content permission', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LocalAiSettingsKeys.allowExplicitContent, true);

    final settings = await LocalAiRuntimeSettings.load();

    expect(settings.allowExplicitContent, isTrue);
  });

  test('local AI runtime settings loads context-window override', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(LocalAiSettingsKeys.aiContextWindowTokens, 32768);

    final settings = await LocalAiRuntimeSettings.load();

    expect(settings.contextWindowOverrideTokens, 32768);
    expect(settings.contextWindowTokens, 32768);
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

  test(
    'local AI runtime settings loads provider-specific cloud API key',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalAiSettingsKeys.localAiMode,
        localAiModeExternalCloud,
      );
      await prefs.setString(LocalAiSettingsKeys.cloudAiProvider, 'Groq');
      await prefs.setString(
        LocalAiSettingsKeys.cloudApiKeys,
        cloudApiKeysToJson({
          cloudApiKeySlot('Google Gemini'): 'gemini_key',
          cloudApiKeySlot('Groq'): 'groq_key',
        }),
      );
      await prefs.setString(LocalAiSettingsKeys.cloudApiKey, 'legacy_key');

      final settings = await LocalAiRuntimeSettings.load();

      expect(settings.cloudApiKey, 'groq_key');
    },
  );

  test(
    'local AI runtime settings keeps built-in cloud models free-only',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalAiSettingsKeys.localAiMode,
        localAiModeExternalCloud,
      );
      await prefs.setString(LocalAiSettingsKeys.cloudAiProvider, 'OpenRouter');
      await prefs.setString(
        LocalAiSettingsKeys.cloudModel,
        'anthropic/claude-sonnet-4.5',
      );

      final settings = await LocalAiRuntimeSettings.load();

      expect(settings.cloudModel, 'openrouter/free');
    },
  );

  test(
    'local AI runtime settings migrates legacy Gemini default model',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalAiSettingsKeys.localAiMode,
        localAiModeExternalCloud,
      );
      await prefs.setString(
        LocalAiSettingsKeys.cloudAiProvider,
        defaultCloudAiProvider,
      );
      await prefs.setString(
        LocalAiSettingsKeys.cloudModel,
        legacyGeminiCloudAiModel,
      );

      final settings = await LocalAiRuntimeSettings.load();

      expect(settings.cloudModel, defaultCloudAiModel);
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
