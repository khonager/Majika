import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/ai/local_ai_service.dart';
import 'package:majika/core/models/recommendation_query.dart';

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

      expect(interpreted.selectedTags, contains('Romance'));
      expect(interpreted.selectedTags, contains('Time Manipulation'));
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

      expect(interpreted.selectedTags, contains('Yandere'));
      expect(interpreted.selectedTags, contains('Thriller'));
    },
  );
}
