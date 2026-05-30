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

  test('local AI service can use an OpenAI-compatible local server', () async {
    Object? requestBody;
    Uri? requestUrl;
    final service = FlutterGemmaLocalAiService(
      settingsLoader: () async => const LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
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

Recommendation _recommendation(String id, String title) {
  return Recommendation(
    item: MediaItem(
      id: id,
      title: title,
      coverUrl: '',
      tags: const ['Mystery'],
    ),
    matchScore: 80,
    reason: 'Reason',
    signals: const ['Mystery'],
  );
}
