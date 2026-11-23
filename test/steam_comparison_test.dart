import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:majika/core/recommendations/taste_engine.dart';
import 'package:majika/core/services/steam_service.dart';

void main() {
  for (final example in <String, String?>{
    'something similar to infamous seconds son. superpowers and open world':
        'infamous seconds son',
    'Anything SIMILIAR TO Stardew Valey? on the couch': 'Stardew Valey',
    'simmilar to Orbit Office but with online co-op': 'Orbit Office',
    'got any recs like Outer Wilds, please?': 'Outer Wilds',
    'not similar to Game One. more like Game Two': 'Game Two',
    'not similar to Game One': null,
    'I just finished Hollow Knight. What else should I try?': 'Hollow Knight',
    'something along the lines of “Mr. Driller” with a controller':
        'Mr. Driller',
    'ゲーム like this': null,
    'games like 大神?': '大神',
    'star janitor vibes but in VR': 'star janitor',
    'a game with cozy vibes': null,
    'relaxing vibes please': null,
    'looking for Stardew Valley vibes': 'Stardew Valley',
    'a game about recovering after a breakup': null,
    'i wanna operate a tower crane': null,
  }.entries) {
    test('reference extraction for "${example.key}"', () {
      expect(
        RecommendationQuery(request: example.key).comparisonReference,
        example.value,
      );
    });
  }

  final profile = TasteProfile.fromJson({'serviceName': 'Steam'});
  http.Response json(Object data) => http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  test(
    'catalog comparisons survive a missing article and obey filters on restore',
    () async {
      final service = SteamService(
        client: MockClient((request) async {
          final uri = request.url;
          switch (uri.path) {
            case '/w/api.php':
              return http.Response('unavailable', 503);
            case '/tagdata/populartags/english':
              return json([
                {'tagid': 1, 'name': 'Automation'},
                {'tagid': 2, 'name': 'Factory'},
              ]);
            case '/api/storesearch/':
              if (uri.queryParameters['term'] == 'Widget Wroks') {
                return json({'items': []});
              }
              expect(uri.queryParameters['term'], 'Widge');
              return json({
                'items': [
                  {'type': 'app', 'id': 10, 'name': 'Widget Works'},
                ],
              });
            case '/IStoreBrowseService/GetItems/v1/':
              return json({
                'response': {
                  'store_items': [
                    {
                      'id': 10,
                      'tagids': [1, 2],
                    },
                  ],
                },
              });
            case '/search/results/':
              expect(uri.queryParameters['tags'], '1,2');
              return json({
                'results_html': [
                  for (final id in [10, 11, 12, 13])
                    '<a data-ds-appid="$id" data-ds-itemkey="App_$id" data-ds-tagids="[1]"></a>',
                  '<a data-ds-appid="99" data-ds-itemkey="Sub_99"></a>',
                ].join(),
              });
            case '/api/appdetails':
              final id = uri.queryParameters['appids']!;
              expect(id, isNot(anyOf('10', '99')));
              return json({
                id: {
                  'success': true,
                  'data': {
                    'type': id == '13' ? 'dlc' : 'game',
                    'name': id == '11' ? 'Night Shift' : 'Conveyor Valley',
                    'categories': [
                      {
                        'description': id == '11'
                            ? 'Single-player'
                            : 'Shared/Split Screen Co-op',
                      },
                    ],
                  },
                },
              });
            default:
              fail('Unexpected request $uri');
          }
        }),
      );
      const request = RecommendationQuery(
        request: 'games like Widget Wroks but with local co-op',
      );
      final results = await service.searchRecommendationCandidates(request);
      expect(results.map((r) => r.id), ['steam_11', 'steam_12']);
      final restored = results
          .map((r) => MediaItem.fromJson(r.toJson()))
          .toList();
      final ownedProfile = TasteEngine().buildProfile('player', [
        restored.last,
      ], serviceName: 'Steam');
      final ranked = TasteEngine().rankCandidates(
        ownedProfile,
        restored,
        query: request,
      );
      expect(ranked.single.item.title, 'Conveyor Valley');
      expect(ranked.single.signals, contains('comparison match'));
    },
  );

  test(
    'index spelling suggestions cannot silently change a numbered sequel',
    () async {
      final terms = <String>[];
      final service = SteamService(
        client: MockClient((request) async {
          final uri = request.url;
          if (uri.path == '/w/api.php') {
            if (uri.queryParameters.containsKey('titles')) {
              expect(uri.queryParameters['titles'], isNot(contains('Pilot 2')));
            }
            return json({
              'query': {
                'searchinfo': {'suggestion': 'Pilot 2'},
                'search': [],
              },
            });
          }
          if (uri.path == '/api/storesearch/') {
            terms.add(uri.queryParameters['term']!);
          }
          return json(uri.path.contains('tagdata') ? [] : {'items': []});
        }),
      );
      expect(
        await service.searchRecommendationCandidates(
          const RecommendationQuery(request: 'games like Pilot 3'),
        ),
        isEmpty,
      );
      expect(terms, contains('Pilot 3'));
      expect(terms, isNot(contains('Pilot 2')));
    },
  );

  // Opt in to external services. Expected titles are assertions, never search inputs.
  if (const bool.fromEnvironment('RUN_LIVE_CATALOG')) {
    final service = SteamService();
    test(
      'live catalog recovers two misspelled activity words',
      () async {
        const query = RecommendationQuery(
          request: 'i wanna operate a towre crnae',
        );
        final results = await service.searchRecommendationCandidates(query);
        final ranked = TasteEngine().rankCandidates(
          profile,
          results,
          query: query,
        );
        expect(
          ranked.map((r) => r.item.title),
          contains('VE GSIM Tower Crane Simulator'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
    for (final example in [
      (
        text:
            'something similar to infamous seconds son. superpowers and open world',
        expected: ['CONTROL Resonant', 'Prototype 2', 'Sunset Overdrive'],
        tag: 'Superhero',
      ),
      (
        text: 'games like hollw knigth, please',
        expected: <String>[],
        tag: 'Metroidvania',
      ),
      (
        text: 'anything like stardew valey? farming and co-op',
        expected: <String>[],
        tag: 'Farming Sim',
      ),
    ]) {
      test(
        'live discovery and ranking: ${example.text}',
        () async {
          final query = RecommendationQuery(request: example.text);
          final items = await service.searchRecommendationCandidates(query);
          final ranked = TasteEngine().rankCandidates(
            profile,
            items,
            query: query,
          );
          final titles = ranked.map((r) => r.item.title).toList();
          // ignore: avoid_print
          print(titles);
          expect(ranked.length, greaterThanOrEqualTo(3));
          expect(titles, containsAll(example.expected));
          expect(ranked.any((r) => r.item.tags.contains(example.tag)), isTrue);
          if (example.expected.isNotEmpty) {
            expect(
              titles.where((s) => s.contains('Spider-Man')).length,
              greaterThanOrEqualTo(2),
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  }
}
